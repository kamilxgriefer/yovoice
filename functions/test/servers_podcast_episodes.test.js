// Podcast Episodes V1 uses the Firestore emulator for lifecycle/ACL and
// deterministic fake adapters for LiveKit Egress and private GCS.
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
    { projectId: "demo-yovoice-servers-podcast-episodes" },
    `server-podcast-episodes-${randomUUID()}`,
  );
  db = firestore.getFirestore(app);
}

const { createServerCreationService } = require("../servers/creation");
const { createServerConvergenceRuntimeService } = require("../servers/convergence_runtime");
const { createServerManagementService } = require("../servers/management");
const {
  PODCAST_AUDIO_CONTENT_TYPE,
  PODCAST_EPISODE_ACCESS_TTL_MS,
  canonicalPodcastEpisodeId,
  createServerPodcastEpisodeService,
  podcastEpisodeStoragePath,
} = require("../servers/podcast_episodes");
const { createServerSessionService } = require("../servers/sessions");

const START_MS = 1_900_000_000_000;
const request = (uid, data, verified = true) => ({
  auth: { uid, token: { email_verified: verified } },
  data,
});
const rejection = (promise, code) => assert.rejects(
  promise,
  (error) => error.code === code,
);
const emulatorTest = (name, fn) => test(`Server Podcast Episodes: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.",
  timeout: 60_000,
}, fn);

after(async () => {
  if (app) await require("firebase-admin/app").deleteApp(app);
});

class FakeEgress {
  constructor() {
    this.recordings = new Map();
    this.ensureCalls = 0;
    this.stopCalls = 0;
    this.completeOnStop = true;
    this.failNextStart = false;
  }

  assertSupported() {
    return true;
  }

  async ensureAudioRecording({ roomName, outputPath }) {
    this.ensureCalls += 1;
    const existing = [...this.recordings.values()].find(
      (item) => item.roomName === roomName && item.outputPath === outputPath &&
        !["failed", "aborted", "limitReached"].includes(item.status),
    );
    if (existing) return { ...existing };
    const value = {
      egressId: `EG_${String(this.ensureCalls).padStart(8, "0")}`,
      roomName,
      outputPath,
      status: this.failNextStart ? "failed" : "active",
    };
    this.failNextStart = false;
    this.recordings.set(value.egressId, value);
    return { ...value };
  }

  async getRecording(egressId, outputPath) {
    const value = this.recordings.get(egressId);
    if (!value || value.outputPath !== outputPath) throw new Error("missing fake egress");
    return { ...value };
  }

  async stopRecording(egressId, outputPath) {
    this.stopCalls += 1;
    const value = this.recordings.get(egressId);
    if (!value || value.outputPath !== outputPath) throw new Error("missing fake egress");
    Object.assign(value, this.completeOnStop
      ? { status: "complete", size: 4096, durationMillis: 60_000 }
      : { status: "ending" });
    return { ...value };
  }

  complete(egressId, { size = 4096, durationMillis = 60_000 } = {}) {
    const value = this.recordings.get(egressId);
    assert.ok(value);
    Object.assign(value, { status: "complete", size, durationMillis });
  }
}

class FakeEpisodeStorage {
  constructor() {
    this.generation = "501";
    this.size = 4096;
    this.contentType = PODCAST_AUDIO_CONTENT_TYPE;
    this.signed = [];
    this.onSign = null;
    this.deleted = [];
  }

  async inspectAudio(storagePath) {
    return {
      storagePath,
      generation: this.generation,
      contentType: this.contentType,
      size: this.size,
    };
  }

  async getSignedReadUrl(path, options) {
    this.signed.push([path, options]);
    if (this.onSign) await this.onSign(path, options);
    return `https://storage.googleapis.com/private-podcasts/${encodeURIComponent(path)}?generation=${options.generation}`;
  }

  async deleteUnpublished(path, options = {}) {
    this.deleted.push({ path, ...options });
  }
}

async function createUser(prefix) {
  const uid = `${prefix}-${randomUUID()}`;
  await db.doc(`users/${uid}`).set({
    displayName: `Canonical ${prefix}`,
    status: "active",
  });
  return uid;
}

async function fixture() {
  const ownerId = await createUser("podcast-owner");
  const clock = { nowMs: START_MS };
  const egress = new FakeEgress();
  const episodeStorage = new FakeEpisodeStorage();
  const livekit = {
    assertSupported: () => true,
    mintToken: async () => { throw new Error("not used"); },
    revokeParticipant: async () => ({ alreadyAbsent: false }),
    endRoom: async () => ({ alreadyAbsent: false }),
  };
  const dependencies = {
    db,
    Timestamp,
    clock: () => clock.nowMs,
    egress,
    episodeStorage,
    randomId: randomUUID,
  };
  const created = await createServerCreationService(dependencies).createServerV1(
    request(ownerId, {
      requestId: randomUUID(),
      serverType: "podcast",
      templateVersion: 1,
      name: "Canonical podcast",
      description: "",
      privacy: "inviteOnly",
      defaultLanguage: "English",
    }),
  );
  await db.doc(`clubs/${created.serverId}`).update({
    status: "active",
    serverActivationState: "active",
  });
  const channels = await db.doc(`clubs/${created.serverId}`).collection("channels").get();
  for (const channel of channels.docs) {
    const roomId = channel.data().roomId;
    if (typeof roomId === "string" && roomId.length > 0) {
      await db.doc(`rooms/${roomId}`).update({
        status: "active",
        serverActivationState: "active",
        hostId: ownerId,
      });
    }
  }
  const studio = channels.docs.find((document) => document.data().kind === "stage");
  const episodes = channels.docs.find((document) => document.data().kind === "episodes");
  const questions = channels.docs.find((document) => document.data().kind === "questions");
  assert.ok(studio);
  assert.ok(episodes);
  assert.ok(questions);
  const session = await createServerSessionService({ ...dependencies, livekit })
    .startServerChannelSessionV1(request(ownerId, {
      serverId: created.serverId,
      channelId: studio.id,
      requestId: randomUUID(),
    }));
  const service = createServerPodcastEpisodeService(dependencies);
  const sessionService = createServerSessionService({ ...dependencies, livekit });
  const management = createServerManagementService(dependencies);
  const convergence = createServerConvergenceRuntimeService({
    ...dependencies,
    livekit,
    podcastEpisodeStorage: episodeStorage,
    familyMemoryStorage: {
      listObjects: async () => [],
      deleteObject: async () => {},
    },
  });

  async function addMember(role = "member") {
    const uid = await createUser(`podcast-${role}`);
    await db.doc(`clubs/${created.serverId}/members/${uid}`).set({
      userId: uid,
      displayName: `Canonical podcast-${role}`,
      photoUrl: null,
      role,
      isOnline: false,
      joinedAt: Timestamp.fromMillis(clock.nowMs),
      invitedBy: ownerId,
      authorizationRevision: 1,
    });
    return uid;
  }

  const startData = (overrides = {}) => ({
    serverId: created.serverId,
    channelId: episodes.id,
    studioChannelId: studio.id,
    sessionId: session.sessionId,
    title: "Episode one",
    requestId: randomUUID(),
    ...overrides,
  });
  const mutateData = (episode, overrides = {}) => ({
    serverId: created.serverId,
    channelId: episodes.id,
    studioChannelId: studio.id,
    episodeId: episode.episodeId,
    expectedRevision: episode.revision,
    requestId: randomUUID(),
    ...overrides,
  });
  const episodeRef = (episodeId) => db.doc(
    `clubs/${created.serverId}/channels/${episodes.id}/episodes/${episodeId}`,
  );

  return {
    ...created,
    ...service,
    ...sessionService,
    ...management,
    ...convergence,
    ownerId,
    clock,
    egress,
    episodeStorage,
    studioChannelId: studio.id,
    episodeChannelId: episodes.id,
    questionChannelId: questions.id,
    sessionId: session.sessionId,
    livekit,
    addMember,
    startData,
    mutateData,
    episodeRef,
  };
}

emulatorTest("start is canonical, exact, role-gated and replay safe", async () => {
  const value = await fixture();
  const data = value.startData();
  const started = await value.startServerPodcastRecordingV1(request(value.ownerId, data));
  assert.equal(started.episodeId, canonicalPodcastEpisodeId(
    value.serverId,
    value.studioChannelId,
    value.sessionId,
  ));
  assert.equal(started.status, "recording");
  assert.equal(started.providerStatus, "active");
  assert.equal(value.egress.ensureCalls, 1);
  assert.equal((await value.episodeRef(started.episodeId).get()).data().outputPath,
    podcastEpisodeStoragePath({
      serverId: value.serverId,
      channelId: value.episodeChannelId,
      episodeId: started.episodeId,
    }));
  assert.deepEqual(await value.startServerPodcastRecordingV1(request(value.ownerId, data)), started);
  assert.equal(value.egress.ensureCalls, 1);

  await rejection(value.startServerPodcastRecordingV1(request(value.ownerId, {
    ...value.startData(), unexpected: true,
  })), "invalid-argument");
  await rejection(value.startServerPodcastRecordingV1(request(value.ownerId,
    value.startData({ channelId: value.questionChannelId }))), "permission-denied");
  const member = await value.addMember();
  await rejection(value.startServerPodcastRecordingV1(request(member, value.startData())),
    "permission-denied");
});

emulatorTest("stop is revision-fenced, durable and reaches ready audio", async () => {
  const value = await fixture();
  const started = await value.startServerPodcastRecordingV1(
    request(value.ownerId, value.startData()),
  );
  await rejection(value.stopServerPodcastRecordingV1(request(value.ownerId,
    value.mutateData(started, { expectedRevision: started.revision + 1 }))), "aborted");
  const data = value.mutateData(started);
  const stopped = await value.stopServerPodcastRecordingV1(request(value.ownerId, data));
  assert.equal(stopped.status, "processing");
  assert.equal(value.egress.stopCalls, 1);
  const ready = (await value.episodeRef(started.episodeId).get()).data();
  assert.equal(ready.status, "ready");
  assert.equal(ready.providerStatus, "complete");
  assert.equal(ready.media.generation, "501");
  assert.equal(ready.media.durationMillis, 60_000);
  assert.equal((await db.doc(`serverPodcastEgressJobs/${started.episodeId}`).get()).exists, false);
  assert.deepEqual(await value.stopServerPodcastRecordingV1(request(value.ownerId, data)), stopped);
  assert.equal(value.egress.stopCalls, 1);
});

emulatorTest("processing can be finalized later and publication is role/revision gated", async () => {
  const value = await fixture();
  value.egress.completeOnStop = false;
  const started = await value.startServerPodcastRecordingV1(
    request(value.ownerId, value.startData()),
  );
  const staged = await value.stopServerPodcastRecordingV1(
    request(value.ownerId, value.mutateData(started)),
  );
  const processing = (await value.episodeRef(started.episodeId).get()).data();
  assert.equal(processing.status, "processing");
  value.egress.complete(processing.egressId);
  const finalized = await value.finalizeServerPodcastEpisodeV1(
    request(value.ownerId, value.mutateData(processing)),
  );
  assert.equal(finalized.status, "ready");
  const member = await value.addMember();
  await rejection(value.publishServerPodcastEpisodeV1(
    request(member, value.mutateData(finalized))), "permission-denied");
  await rejection(value.publishServerPodcastEpisodeV1(request(value.ownerId,
    value.mutateData(finalized, { expectedRevision: staged.revision }))), "aborted");
  const published = await value.publishServerPodcastEpisodeV1(
    request(value.ownerId, value.mutateData(finalized)),
  );
  assert.equal(published.status, "published");
});

emulatorTest("signed playback is generation-bound and rechecks membership after signing", async () => {
  const value = await fixture();
  const started = await value.startServerPodcastRecordingV1(
    request(value.ownerId, value.startData()),
  );
  await value.stopServerPodcastRecordingV1(
    request(value.ownerId, value.mutateData(started)),
  );
  const ready = (await value.episodeRef(started.episodeId).get()).data();
  const published = await value.publishServerPodcastEpisodeV1(
    request(value.ownerId, value.mutateData(ready)),
  );
  const member = await value.addMember();
  const input = {
    serverId: value.serverId,
    channelId: value.episodeChannelId,
    episodeId: published.episodeId,
  };
  const access = await value.getServerPodcastEpisodeAccessV1(request(member, input));
  assert.equal(access.expiresAtMillis, START_MS + PODCAST_EPISODE_ACCESS_TTL_MS);
  assert.equal(access.media.generation, "501");
  assert.match(access.media.url, /^https:\/\/storage[.]googleapis[.]com\//u);
  value.episodeStorage.onSign = async () => {
    await db.doc(`clubs/${value.serverId}/members/${member}`).delete();
  };
  await rejection(value.getServerPodcastEpisodeAccessV1(request(member, input)),
    "permission-denied");
});

emulatorTest("provider failure is explicit and a live moderator can retry", async () => {
  const value = await fixture();
  value.egress.failNextStart = true;
  const failed = await value.startServerPodcastRecordingV1(
    request(value.ownerId, value.startData()),
  );
  assert.equal(failed.status, "error");
  assert.equal(failed.providerStatus, "failed");
  const retryData = value.mutateData(failed);
  const retried = await value.retryServerPodcastRecordingV1(
    request(value.ownerId, retryData),
  );
  assert.equal(retried.status, "recording");
  assert.equal(retried.providerStatus, "active");
  assert.equal(value.egress.ensureCalls, 2);
  assert.deepEqual(
    await value.retryServerPodcastRecordingV1(request(value.ownerId, retryData)),
    retried,
  );
  assert.equal(value.egress.ensureCalls, 2);
});

emulatorTest("provider/object mismatch stays processing and remains retryable", async () => {
  const value = await fixture();
  value.egress.completeOnStop = false;
  const started = await value.startServerPodcastRecordingV1(
    request(value.ownerId, value.startData()),
  );
  await value.stopServerPodcastRecordingV1(
    request(value.ownerId, value.mutateData(started)),
  );
  const processing = (await value.episodeRef(started.episodeId).get()).data();
  value.egress.complete(processing.egressId, { size: 8192 });
  await rejection(value.finalizeServerPodcastEpisodeV1(
    request(value.ownerId, value.mutateData(processing))), "unavailable");
  assert.equal((await value.episodeRef(started.episodeId).get()).data().status, "processing");
  assert.equal((await db.doc(`serverPodcastEgressJobs/${started.episodeId}`).get()).exists, true);
});

async function serverDeleteJob(serverId) {
  const page = await db.collection("serverControlOutbox")
    .where("serverId", "==", serverId)
    .get();
  const matches = page.docs.filter((document) => document.data().kind === "serverDelete");
  assert.equal(matches.length, 1);
  return matches[0];
}

async function drainServerDeletion(value, operationId, { onPage = null } = {}) {
  let result;
  for (let page = 0; page < 300; page += 1) {
    result = await value.processServerConvergencePage({ operationId, pageSize: 2 });
    if (onPage) await onPage();
    if (!result.cleanupPending) return result;
  }
  assert.fail("Podcast server deletion did not finish within its bounded test pages.");
}

emulatorTest("server deletion drains a published episode, its state and exact Storage generation", async () => {
  const value = await fixture();
  const started = await value.startServerPodcastRecordingV1(
    request(value.ownerId, value.startData()),
  );
  await value.stopServerPodcastRecordingV1(
    request(value.ownerId, value.mutateData(started)),
  );
  const ready = (await value.episodeRef(started.episodeId).get()).data();
  await value.publishServerPodcastEpisodeV1(
    request(value.ownerId, value.mutateData(ready)),
  );
  await value.endServerChannelSessionV1(request(value.ownerId, {
    serverId: value.serverId,
    channelId: value.studioChannelId,
    sessionId: value.sessionId,
    requestId: randomUUID(),
  }));
  await value.deleteServerV1(request(value.ownerId, {
    serverId: value.serverId,
    requestId: randomUUID(),
  }));
  const deletion = await serverDeleteJob(value.serverId);
  const result = await drainServerDeletion(value, deletion.id);
  assert.equal(result.cleanupPending, false);
  assert.equal((await value.episodeRef(started.episodeId).get()).exists, false);
  assert.equal((await db.doc(
    `clubs/${value.serverId}/channels/${value.studioChannelId}/podcastRecordingState/main`,
  ).get()).exists, false);
  assert.equal((await db.doc(`serverPodcastEgressJobs/${started.episodeId}`).get()).exists, false);
  assert.deepEqual(value.episodeStorage.deleted, [{
    path: podcastEpisodeStoragePath({
      serverId: value.serverId,
      channelId: value.episodeChannelId,
      episodeId: started.episodeId,
    }),
    generation: "501",
  }]);
  assert.equal((await db.doc(`clubs/${value.serverId}`).get()).exists, false);
});

emulatorTest("deletion converts a live Egress job to stop, waits, then resumes without stranding audio", async () => {
  const value = await fixture();
  value.egress.completeOnStop = true;
  const started = await value.startServerPodcastRecordingV1(
    request(value.ownerId, value.startData()),
  );
  const marked = await value.staffDeleteServer({
    serverId: value.serverId,
    actorUid: `staff-${randomUUID()}`,
  });
  const deletion = await serverDeleteJob(value.serverId);
  assert.equal(marked.operationId, deletion.id);
  let reconciledStop = false;
  const result = await drainServerDeletion(value, deletion.id, {
    onPage: async () => {
      const snapshot = await db.doc(`serverPodcastEgressJobs/${started.episodeId}`).get();
      if (!snapshot.exists || snapshot.data().action !== "stop" || reconciledStop) return;
      const episode = (await value.episodeRef(started.episodeId).get()).data();
      assert.equal(episode.status, "processing");
      assert.equal(episode.providerStatus, "ending");
      reconciledStop = true;
      await value.processPodcastEgressJob(started.episodeId, { force: true });
    },
  });
  assert.equal(result.cleanupPending, false);
  assert.equal(reconciledStop, true);
  assert.equal(value.egress.stopCalls, 1);
  assert.equal((await db.doc(`serverPodcastEgressJobs/${started.episodeId}`).get()).exists, false);
  assert.equal((await db.doc(`clubs/${value.serverId}`).get()).exists, false);
  assert.equal(value.episodeStorage.deleted.length, 1);
  assert.equal(value.episodeStorage.deleted[0].generation, "501");
});

const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

// Independent root QA. Real local Firestore transactions + the production
// server adapter, with an explicitly injected, test-only provider transport.
// This does not contact LiveKit or activate a real server/customer account.
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let app; let db; let Timestamp;
if (enabled) {
  const admin = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = admin.initializeApp({ projectId: "demo-yovoice-terminal-independent" }, `terminal-qa-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

const { createServerCreationService } = require("../servers/creation");
const { createServerSessionService } = require("../servers/sessions");
const { createServerSessionControlService } = require("../servers/session_control");
const { createServerLiveKitAdapter } = require("../servers/session_livekit");
const { tokenRecipientId } = require("../servers/session_contract");
const { canonicalLiveKitRoomName } = require("../servers/contract");

const qa = (name, action) => test(`Independent terminal deletion: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.", timeout: 60_000,
}, action);
const req = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const tick = () => new Promise((resolve) => setImmediate(resolve));
const gate = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
};

async function fixture(count = 1) {
  const uid = `terminal-owner-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  const hooks = { remove: null, delete: null, beforeDelete: null, failFinalCommit: false };
  const calls = [];
  let inFlight = 0; let maxInFlight = 0;
  let endJobPath = null;
  // Fault only the final acknowledgment transaction, before commit. The
  // previously committed recipient checkpoint must survive this failure.
  const database = new Proxy(db, {
    get(target, key) {
      if (key === "runTransaction") return (action, ...options) => target.runTransaction(async (transaction) => {
        let isFinal = false;
        const wrapped = new Proxy(transaction, {
          get(tx, member) {
            if (member === "update") return (reference, data, ...rest) => {
              if (reference.path === endJobPath && data?.status === "completed") isFinal = true;
              tx.update(reference, data, ...rest);
              return wrapped;
            };
            const value = tx[member];
            return typeof value === "function" ? value.bind(tx) : value;
          },
        });
        const result = await action(wrapped);
        if (isFinal && hooks.failFinalCommit) {
          hooks.failFinalCommit = false;
          throw new Error("Independent test: final ACK commit was lost.");
        }
        return result;
      }, ...options);
      const value = target[key];
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  await db.doc(`users/${uid}`).set({ displayName: "Terminal QA owner", status: "active" });
  const dependencies = { db: database, Timestamp, clock };
  const created = await createServerCreationService(dependencies).createServerV1(req(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Terminal deletion QA", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const server = db.doc(`clubs/${created.serverId}`);
  const channels = await server.collection("channels").where("kind", "==", "voice").get();
  const channel = channels.docs[0].ref;
  const roomId = channels.docs[0].data().roomId;
  const room = db.doc(`rooms/${roomId}`);
  // Fresh UUID records in the hard-coded demo project only.
  await server.update({ status: "active", serverActivationState: "active" });
  await room.update({ status: "active", serverActivationState: "active", hostId: uid });
  const transport = {
    async removeParticipant(roomName, actor, options) {
      calls.push({ type: "remove", roomName, actor, options });
      inFlight++; maxInFlight = Math.max(maxInFlight, inFlight);
      try { await tick(); return hooks.remove ? await hooks.remove(actor, roomName, options) : {}; }
      finally { inFlight--; }
    },
    async deleteRoom(roomName) {
      calls.push({ type: "delete", roomName });
      inFlight++; maxInFlight = Math.max(maxInFlight, inFlight);
      try { return hooks.delete ? await hooks.delete(roomName) : {}; }
      finally { inFlight--; }
    },
    async listParticipants() { calls.push({ type: "forbidden-list" }); throw new Error("No roster scan is allowed."); },
    async getParticipant() { calls.push({ type: "forbidden-get" }); throw new Error("No participant lookup is allowed."); },
    async listRooms() { calls.push({ type: "forbidden-rooms" }); throw new Error("No global scan is allowed."); },
  };
  const adapter = createServerLiveKitAdapter({
    apiKey: () => "independent-test-key", apiSecret: () => "independent-test-secret",
    serverUrl: () => "wss://independent-terminal.livekit.cloud", client: transport, clock,
  });
  const provider = {
    ...adapter,
    async mintToken(input) {
      const token = `test-only-${randomUUID()}`;
      return { serverUrl: "wss://independent-terminal.livekit.cloud", token, participantToken: token,
        roomName: input.binding.livekitRoomName, participantIdentity: input.uid,
        participantName: input.participantName, expiresAtMillis: clock() + 300_000,
        permissions: { canPublish: input.grant.canPublish, canSubscribe: input.grant.canSubscribe,
          canPublishData: input.grant.canPublishData }, permittedTrackSources: input.grant.permittedTrackSources,
        serverId: input.binding.serverId, channelId: input.binding.channelId,
        roomId: input.binding.roomId, sessionId: input.binding.sessionId, sessionRole: input.sessionRole };
    },
    async endRoom(...args) {
      if (hooks.beforeDelete) await hooks.beforeDelete(...args);
      return adapter.endRoom(...args);
    },
  };
  const service = createServerSessionService({ ...dependencies, livekit: provider });
  const control = createServerSessionControlService({ ...dependencies, livekit: provider });
  const target = { serverId: server.id, channelId: channel.id };
  const session = (id) => channel.collection("channelSessions").doc(id);
  const start = () => service.startServerChannelSessionV1(req(uid, { ...target, requestId: randomUUID() }));
  const token = (id, actor = uid) => service.createServerChannelTokenV1(req(actor, {
    ...target, sessionId: id, requestId: randomUUID(),
  }));
  const begun = await start();
  const actors = [];
  for (let index = 0; index < count; index++) {
    const actor = index === 0 ? uid : `terminal-member-${randomUUID()}`;
    if (index > 0) {
      await db.doc(`users/${actor}`).set({ displayName: "Terminal QA member", status: "active" });
      await server.collection("members").doc(actor).set({ userId: actor, role: "member", authorizationRevision: 1, isOnline: false });
    }
    actors.push(actor);
    await token(begun.sessionId, actor);
  }
  const recipient = (actor = uid) => session(begun.sessionId).collection("tokenRecipients").doc(tokenRecipientId(actor));
  return { uid, actors, channel, room, roomId, target, session, recipient, control, adapter, calls, hooks,
    sessionId: begun.sessionId, start, token, clock, advance: (ms) => { nowMs += ms; },
    maxInFlight: () => maxInFlight, inFlight: () => inFlight,
    participant: () => room.collection("participants").doc(uid),
    mirror: () => db.doc(`activeVoiceSessions/${uid}/rooms/${roomId}`),
    job: async () => {
      const data = (await session(begun.sessionId).get()).data();
      const reference = db.doc(`serverControlOutbox/${data.endOperationId}`);
      endJobPath = reference.path;
      return reference;
    },
    end: () => service.endServerChannelSessionV1(req(uid, {
      ...target, sessionId: begun.sessionId, requestId: randomUUID(),
    })),
  };
}

qa("legacy, absent and cross-generation context never reaches the provider", async () => {
  const f = await fixture(0);
  const binding = { version: 1, ...f.target, roomId: f.roomId, sessionId: f.sessionId, endOperationId: "fake-end" };
  const name = canonicalLiveKitRoomName(f.target.serverId, f.target.channelId, f.sessionId);
  for (const [room, context] of [[name, undefined], [name, {}], [f.roomId, binding],
    [name, { ...binding, sessionId: "other" }], [name, { ...binding, serverId: "other" }]]) {
    await assert.rejects(Promise.resolve().then(() => f.adapter.endRoom(room, context)));
  }
  assert.equal(f.calls.length, 0);
  assert.equal((await f.session(f.sessionId).get()).data().status, "live");
});

for (const count of [0, 19, 20, 21]) qa(`${count} issued identities: every pass has at most 20 real adapter RPCs`, async () => {
  const f = await fixture(count);
  let before = f.calls.length;
  let result = await f.end();
  assert.ok(f.calls.length - before <= 20);
  if (count === 20) {
    assert.equal(result.cleanupPending, true);
    assert.equal(f.calls.filter((call) => call.type === "delete").length, 0);
  }
  const job = await f.job();
  for (let pass = 0; result.cleanupPending && pass < 3; pass++) {
    before = f.calls.length;
    result = await f.control.processServerSessionEndPage({ operationId: job.id });
    assert.ok(f.calls.length - before <= 20);
  }
  assert.equal(result.cleanupPending, false);
  assert.equal(f.calls.filter((call) => call.type === "remove").length, count);
  assert.equal(f.calls.filter((call) => call.type === "delete").length, 1);
  assert.ok(f.calls.every((call) => ["remove", "delete"].includes(call.type)));
  assert.ok(f.maxInFlight() <= 4);
  assert.equal(f.inFlight(), 0);
  for (const actor of f.actors) {
    const receipt = (await f.recipient(actor).get()).data();
    assert.equal(receipt.revocationState, "revoked");
    assert.ok(receipt.revokedBeforeMillis > 0);
  }
  assert.equal((await f.session(f.sessionId).get()).data().status, "ended");
});

qa("remote deletion with a lost ACK retries only delete, never already-settled removals", async () => {
  const f = await fixture(2);
  let roomDeleted = false;
  f.hooks.remove = () => {
    if (roomDeleted) throw Object.assign(new Error("Room already absent"), { code: "not_found" });
    return {};
  };
  f.hooks.delete = async () => {
    for (const actor of f.actors) {
      const receipt = (await f.recipient(actor).get()).data();
      assert.equal(receipt.revocationState, "revoked");
      assert.ok(receipt.revokedBeforeMillis > 0);
    }
    if (!roomDeleted) {
      roomDeleted = true;
      throw Object.assign(new Error("Deleted remotely, response lost"), { code: "deadline_exceeded" });
    }
    throw Object.assign(new Error("Terminal room absent"), { code: "not_found" });
  };
  const first = await f.end();
  assert.equal(first.cleanupPending, true);
  assert.equal(f.calls.filter((call) => call.type === "delete").length, 1);
  const job = await f.job();
  assert.equal((await f.session(f.sessionId).get()).data().status, "ending");
  const retry = await f.control.processServerSessionEndPage({ operationId: job.id });
  assert.equal(retry.cleanupPending, false);
  assert.equal(f.calls.filter((call) => call.type === "remove").length, 2);
  assert.equal(f.calls.filter((call) => call.type === "delete").length, 2);
  assert.equal((await job.get()).data().status, "completed");
});

qa("a process interruption before delete retains receipts and resumes with one terminal RPC", async () => {
  const f = await fixture();
  f.hooks.beforeDelete = () => { throw new Error("Test process interrupted before dispatch"); };
  assert.equal((await f.end()).cleanupPending, true);
  assert.equal((await f.recipient().get()).data().revocationState, "revoked");
  assert.deepEqual(f.calls.map((call) => call.type), ["remove"]);
  const job = await f.job();
  f.hooks.beforeDelete = null;
  assert.equal((await f.control.processServerSessionEndPage({ operationId: job.id })).cleanupPending, false);
  assert.deepEqual(f.calls.map((call) => call.type), ["remove", "delete"]);
});

qa("final ACK transaction failure does not roll back the earlier revocation checkpoint", async () => {
  const f = await fixture();
  f.hooks.beforeDelete = async () => {
    await f.job();
    f.hooks.failFinalCommit = true;
    f.hooks.beforeDelete = null;
  };
  assert.equal((await f.end()).cleanupPending, true);
  assert.equal((await f.recipient().get()).data().revocationState, "revoked");
  assert.equal((await f.session(f.sessionId).get()).data().status, "ending");
  const job = await f.job();
  assert.equal((await f.control.processServerSessionEndPage({ operationId: job.id })).cleanupPending, false);
  assert.deepEqual(f.calls.map((call) => call.type), ["remove", "delete", "delete"]);
  assert.equal((await job.get()).data().status, "completed");
});

qa("one failed removal waits for every started peer before releasing its lease", async () => {
  const f = await fixture(3);
  const entered = gate(); const release = gate();
  f.hooks.remove = async (actor) => {
    if (actor === f.actors[0]) throw new Error("Test first removal failed");
    if (actor === f.actors[1]) { entered.resolve(); await release.promise; }
    return {};
  };
  let settled = false;
  const pending = f.end().then((value) => { settled = true; return value; });
  await entered.promise;
  try {
    await tick(); await tick();
    assert.equal(settled, false);
    const job = await f.job();
    assert.notEqual((await job.get()).data().leaseId, null);
    assert.equal(f.calls.filter((call) => call.type === "delete").length, 0);
  } finally { release.resolve(); }
  assert.equal((await pending).cleanupPending, true);
  assert.equal(f.inFlight(), 0);
  const job = await f.job();
  assert.equal((await job.get()).data().cursor, null);
  assert.equal((await job.get()).data().leaseId, null);
});

qa("participant NOT_FOUND cannot be substituted for a positive cutoff receipt", async () => {
  const f = await fixture();
  f.hooks.remove = () => { throw Object.assign(new Error("Offline, not a cutoff ACK"), { code: "not_found" }); };
  assert.equal((await f.end()).cleanupPending, true);
  const job = await f.job();
  assert.equal((await job.get()).data().cursor, null);
  assert.equal((await f.recipient().get()).data().revocationState, "revoking");
  assert.deepEqual(f.calls.map((call) => call.type), ["remove"]);
});

qa("late terminal ACK after lease takeover cannot disturb an actually started new generation", async () => {
  const f = await fixture();
  const entered = gate(); const release = gate();
  f.hooks.delete = async () => { entered.resolve(); await release.promise; return {}; };
  const stale = f.end();
  await entered.promise;
  try {
    const job = await f.job();
    f.advance(120_001);
    f.hooks.delete = null;
    assert.equal((await f.control.processServerSessionEndPage({ operationId: job.id })).cleanupPending, false);
    const next = await f.start();
    await f.token(next.sessionId);
    const [room, participant, mirror] = await Promise.all([f.room.get(), f.participant().get(), f.mirror().get()]);
    release.resolve(); await stale;
    assert.deepEqual((await f.room.get()).data(), room.data());
    assert.deepEqual((await f.participant().get()).data(), participant.data());
    assert.deepEqual((await f.mirror().get()).data(), mirror.data());
    assert.equal((await f.channel.get()).data().activeSessionId, next.sessionId);
    assert.equal(f.calls.filter((call) => call.type === "remove").length, 1);
    assert.ok(f.calls.every((call) => call.roomName !== room.data().livekitRoomName));
  } finally { release.resolve(); await Promise.allSettled([stale]); }
});

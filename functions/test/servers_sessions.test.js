const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
let db; let app; let Timestamp;
if (enabled) {
  const admin = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = admin.initializeApp({ projectId: "demo-yovoice-server-runtime" }, `server-runtime-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
const { createServerCreationService } = require("../servers/creation");
const { createServerChannelService } = require("../servers/channels");
const { createServerSessionService } = require("../servers/sessions");
const { createServerSessionControlService } = require("../servers/session_control");
const { createServerLiveKitAdapter } = require("../servers/session_livekit");
const { tokenRecipientId, SESSION_TOKEN_ATTEMPT_SCOPE } = require("../servers/session_contract");
const { canonicalLiveKitRoomName } = require("../servers/contract");
const { grantDocument } = require("../servers/authority");
const { digest, rateLimitReference } = require("../integrity/guards");
const emulatorTest = (name, fn) => test(name, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 45_000,
}, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const reject = (promise, code) => assert.rejects(promise, (error) => error.code === code);
const gate = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
};
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

function databaseWithTransactionFaults(hooks) {
  return new Proxy(db, { get(target, property) {
    if (property === "runTransaction") return async (action, ...options) => {
      if (hooks.beforeTransaction) await hooks.beforeTransaction();
      const writes = [];
      const result = await target.runTransaction((transaction) => action(new Proxy(transaction, {
        get(actual, key) {
          if (key === "update") return (reference, patch, ...rest) => {
            writes.push({ path: reference.path, patch });
            return actual.update(reference, patch, ...rest);
          };
          const value = Reflect.get(actual, key, actual);
          return typeof value === "function" ? value.bind(actual) : value;
        },
      })), ...options);
      if (hooks.afterTransaction) await hooks.afterTransaction(writes);
      return result;
    };
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
}

async function fixture({ kind = "voice", mediaMode = null, held = false, runtimeDb = db, controlAdapter = null } = {}) {
  const uid = `runtime-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "Runtime owner", status: "active" });
  const dependencies = { db: runtimeDb, Timestamp, clock };
  const root = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Runtime fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const channelService = createServerChannelService(dependencies);
  let channel;
  if (kind === "voice") channel = (await db.collection(`clubs/${root.serverId}/channels`).where("kind", "==", "voice").get()).docs[0];
  else {
    const result = await channelService.createServerChannelV1(request(uid, {
      serverId: root.serverId, requestId: randomUUID(), kind, name: "Media fixture", categoryId: null,
      accessMode: "members", experience: kind === "stage" ? "broadcast" : "community",
      mediaMode: mediaMode ?? (kind === "stage" ? "audio" : "meeting"),
    }));
    channel = await db.doc(`clubs/${root.serverId}/channels/${result.channelId}`).get();
  }
  const roomId = channel.data().roomId;
  // These are isolated emulator fixtures, not an activation function or a
  // production migration. Created graphs themselves remain held by default.
  if (!held) {
    await db.doc(`clubs/${root.serverId}`).update({ status: "active", serverActivationState: "active" });
    await db.doc(`rooms/${roomId}`).update({ status: "active", serverActivationState: "active", hostId: uid });
  }
  const calls = { signed: [], revoked: [], ended: [] };
  let signingHook = null; let revokeHook = null; let endHook = null;
  const livekit = {
    assertSupported() { return "wss://test-fixture.livekit.cloud"; },
    async mintToken(value) {
      calls.signed.push(value);
      if (signingHook) await signingHook(value);
      const token = `test-only-token-${randomUUID()}`;
      return { serverUrl: "wss://test-fixture.livekit.cloud", participantToken: token, token,
        roomName: value.binding.livekitRoomName, participantIdentity: value.uid,
        participantName: value.participantName, expiresAtMillis: nowMs + 300_000,
        permissions: { canPublish: value.grant.canPublish, canSubscribe: true, canPublishData: true },
        permittedTrackSources: value.grant.permittedTrackSources,
        serverId: value.binding.serverId, channelId: value.binding.channelId,
        roomId: value.binding.roomId, sessionId: value.binding.sessionId, sessionRole: value.sessionRole };
    },
    async revokeParticipant(roomName, userId) {
      calls.revoked.push({ roomName, userId });
      const result = revokeHook ? await revokeHook(roomName, userId) : { alreadyAbsent: false };
      return { revokedBeforeMillis: (Math.floor(nowMs / 1000) + 1) * 1000, ...result };
    },
    async endRoom(roomName) { calls.ended.push(roomName); return endHook ? await endHook(roomName) : {}; },
  };
  const media = controlAdapter === null ? livekit : { ...livekit,
    assertSupported: controlAdapter.assertSupported, revokeParticipant: controlAdapter.revokeParticipant,
    endRoom: controlAdapter.endRoom };
  const service = createServerSessionService({ ...dependencies, livekit: media });
  const control = createServerSessionControlService({ ...dependencies, livekit: media });
  const target = { serverId: root.serverId, channelId: channel.id };
  const startData = { ...target, requestId: randomUUID() };
  return { uid, root, target, channel, roomId, calls, service, control, channelService,
    advance: (ms) => { nowMs += ms; }, clock,
    onSign: (hook) => { signingHook = hook; }, onRevoke: (hook) => { revokeHook = hook; }, onEnd: (hook) => { endHook = hook; },
    startData, start: () => service.startServerChannelSessionV1(request(uid, startData)),
    token: (sessionId, actor = uid, requestId = randomUUID()) => service.createServerChannelTokenV1(request(actor, { ...target, sessionId, requestId })),
    end: (sessionId, actor = uid, requestId = randomUUID()) => service.endServerChannelSessionV1(request(actor, { ...target, sessionId, requestId })),
    member: async (role = "member") => {
      const userId = `runtime-member-${randomUUID()}`;
      await db.doc(`users/${userId}`).set({ displayName: "Runtime member", status: "active" });
      await db.doc(`clubs/${root.serverId}/members/${userId}`).set({ userId, role, authorizationRevision: 1 });
      return userId;
    },
  };
}

emulatorTest("start is atomic/idempotent under concurrency and creates no token, roster or fake presence", async () => {
  const f = await fixture();
  const results = await Promise.all([f.start(), f.start(), f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() }))]);
  assert.equal(new Set(results.map((result) => result.sessionId)).size, 1);
  const sessionId = results[0].sessionId;
  const channel = (await f.channel.ref.get()).data();
  const room = (await db.doc(`rooms/${f.roomId}`).get()).data();
  assert.equal(channel.activeSessionId, sessionId);
  assert.equal(room.voiceSessionId, sessionId);
  assert.equal(room.hostId, f.uid);
  assert.equal(room.livekitRoomName, canonicalLiveKitRoomName(f.target.serverId, f.target.channelId, sessionId));
  assert.equal((await db.collection(`rooms/${f.roomId}/participants`).get()).size, 0);
  assert.equal((await db.collection(`activeVoiceSessions/${f.uid}/rooms`).get()).size, 0);
  assert.equal((await db.doc(`clubs/${f.target.serverId}`).get()).data().onlineCount, 0);
  assert.equal(f.calls.signed.length, 0);
});

emulatorTest("held, unknown and archived roots/channels deny start and never write runtime state", async () => {
  const f = await fixture({ held: true });
  await reject(f.start(), "permission-denied");
  for (const patch of [{ serverSchemaVersion: 2, status: "active", serverActivationState: "active" },
    { serverSchemaVersion: 1, status: "archived" }, { status: "active", serverType: "unknown" }]) {
    await db.doc(`clubs/${f.target.serverId}`).update(patch);
    await reject(f.start(), "permission-denied");
  }
  assert.equal((await f.channel.ref.collection("channelSessions").get()).size, 0);
  const active = await fixture();
  await active.channel.ref.update({ status: "archived" });
  await reject(active.start(), "permission-denied");
});

emulatorTest("guest memberships, strangers and mismatched owner/room bindings cannot start", async () => {
  const f = await fixture();
  const guest = await f.member("guest");
  await reject(f.service.startServerChannelSessionV1(request(guest, f.startData)), "permission-denied");
  const stranger = `outsider-${randomUUID()}`;
  await db.doc(`users/${stranger}`).set({ displayName: "Outsider" });
  await reject(f.service.startServerChannelSessionV1(request(stranger, f.startData)), "permission-denied");
  await db.doc(`rooms/${f.roomId}`).update({ hostId: stranger });
  await reject(f.start(), "permission-denied");
});

emulatorTest("explicit token join uses canonical session roles, preserves owner binding and counts no online presence", async () => {
  const f = await fixture({ kind: "stage", mediaMode: "video" });
  const { sessionId } = await f.start();
  const member = await f.member();
  const owner = await f.token(sessionId);
  const listener = await f.token(sessionId, member);
  assert.deepEqual(owner.permittedTrackSources, ["microphone", "camera"]);
  assert.equal(owner.sessionRole, "host");
  assert.equal(listener.sessionRole, "listener");
  assert.equal(listener.permissions.canPublish, false);
  assert.deepEqual(listener.permittedTrackSources, []);
  const roster = (await db.doc(`rooms/${f.roomId}/participants/${member}`).get()).data();
  assert.equal(roster.isMuted, true);
  const mirror = (await db.doc(`activeVoiceSessions/${member}/rooms/${f.roomId}`).get()).data();
  assert.equal(mirror.livekitRoomName, owner.roomName);
  assert.equal(mirror.roomId, f.roomId);
  assert.equal(mirror.sessionId, sessionId);
  assert.equal(mirror.participantIdentity, member);
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().participantCount, 0);
});

emulatorTest("parallel same-request tokens share a receipt and every replay consumes target-independent budget", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
  const results = await Promise.all([f.token(sessionId, f.uid, id), f.token(sessionId, f.uid, id)]);
  assert.deepEqual(results[0], results[1]);
  assert.deepEqual(await f.token(sessionId, f.uid, id), results[0]);
  assert.equal((await rateLimitReference(db, SESSION_TOKEN_ATTEMPT_SCOPE, f.uid).get()).data().count, 3);
  assert.equal((await f.channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).get()).size, 1);
});

emulatorTest("cached JWT replay reauthorizes membership, sanctions, root and session state", async () => {
  for (const mutate of [
    (f) => db.doc(`clubs/${f.target.serverId}/members/${f.uid}`).update({ authorizationRevision: 2 }),
    (f) => db.doc(`restrictions/${f.uid}`).set({ type: "communicationMute", expiresAt: null }),
    (f) => db.doc(`clubs/${f.target.serverId}`).update({ serverActivationState: "held", status: "preparing" }),
    (f, sessionId) => f.channel.ref.collection("channelSessions").doc(sessionId).update({ status: "ended" }),
  ]) {
    const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
    await f.token(sessionId, f.uid, id);
    await mutate(f, sessionId);
    await reject(f.token(sessionId, f.uid, id), "permission-denied");
    assert.equal(f.calls.signed.length, 1);
  }
});

emulatorTest("membership/ACL changes while signing prevent token disclosure and all admission writes", async () => {
  for (const mutate of [
    (f) => db.doc(`clubs/${f.target.serverId}/members/${f.uid}`).update({ authorizationRevision: 2 }),
    (f) => f.channel.ref.update({ aclRevision: 2, revision: 3 }),
  ]) {
    const f = await fixture(); const { sessionId } = await f.start();
    f.onSign(() => mutate(f));
    await reject(f.token(sessionId), "aborted");
    assert.equal((await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).get()).exists, false);
    assert.equal((await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`).get()).exists, false);
    assert.equal((await f.channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).get()).size, 0);
  }
});

emulatorTest("restricted channel grants are checked against both current revisions at token issue", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const member = await f.member();
  const channel = { ...(await f.channel.ref.get()).data(), accessMode: "restricted", isPrivate: true,
    accessPolicy: { accessMode: "restricted", roleIds: ["owner", "member"], userIds: [] }, aclRevision: 2 };
  await f.channel.ref.set(channel);
  const membership = (await db.doc(`clubs/${f.target.serverId}/members/${member}`).get()).data();
  await f.channel.ref.collection("accessGrants").doc(member).set(grantDocument({ uid: member,
    serverId: f.target.serverId, channelId: f.target.channelId, member: membership, channel, now: Timestamp.now() }));
  await f.token(sessionId, member);
  await f.channel.ref.collection("accessGrants").doc(member).update({ membershipRevision: 1, aclRevision: 1 });
  await reject(f.token(sessionId, member), "permission-denied");
});

emulatorTest("changed request input and expired token receipts do not mint replacement JWTs", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
  await f.token(sessionId, f.uid, id);
  await reject(f.token("foreign-session", f.uid, id), "permission-denied");
  f.advance(300_001);
  await reject(f.token(sessionId, f.uid, id), "already-exists");
  assert.equal(f.calls.signed.length, 1);
});

emulatorTest("end authority is starter or channel moderator, not every member who can start", async () => {
  const f = await fixture(); const member = await f.member(); const other = await f.member();
  const start = await f.service.startServerChannelSessionV1(request(member, { ...f.startData, requestId: randomUUID() }));
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().hostId, f.uid);
  assert.equal((await f.token(start.sessionId, member)).sessionRole, "host");
  await reject(f.end(start.sessionId, other), "permission-denied");
  const ended = await f.end(start.sessionId, f.uid);
  assert.equal(ended.status, "ended");
});

emulatorTest("end revokes never-connected token recipients before delete and retains all session history", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const member = await f.member();
  const token = await f.token(sessionId, member);
  await db.doc(`rooms/${f.roomId}/participants/${member}`).delete();
  const result = await f.end(sessionId);
  assert.equal(result.cleanupPending, false);
  assert.deepEqual(f.calls.revoked, [{ roomName: token.roomName, userId: member }]);
  assert.deepEqual(f.calls.ended, [token.roomName]);
  assert.equal((await db.doc(`activeVoiceSessions/${member}/rooms/${f.roomId}`).get()).exists, false);
  const session = await f.channel.ref.collection("channelSessions").doc(sessionId).get();
  assert.equal(session.data().status, "ended");
  assert.equal((await session.ref.collection("tokenRecipients").doc(tokenRecipientId(member)).get()).data().revocationState, "revoked");
  assert.equal((await f.channel.ref.get()).exists, true);
  assert.equal((await db.doc(`clubs/${f.target.serverId}`).get()).exists, true);
});

emulatorTest("provider absence/failure retains durable barrier; retry closes old generation without touching new", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const token = await f.token(sessionId);
  f.onRevoke(() => ({ alreadyAbsent: true }));
  const requestId = randomUUID(); const pending = await f.end(sessionId, f.uid, requestId);
  assert.equal(pending.cleanupPending, true);
  assert.equal(f.calls.ended.length, 0);
  await reject(f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() })), "failed-precondition");
  await reject(f.token(sessionId), "permission-denied");
  f.onRevoke(null);
  assert.equal((await f.end(sessionId, f.uid, requestId)).cleanupPending, false);
  const next = await f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() }));
  assert.notEqual(next.sessionId, sessionId);
  assert.notEqual(canonicalLiveKitRoomName(f.target.serverId, f.target.channelId, next.sessionId), token.roomName);
  assert.deepEqual(await f.start(), { roomId: f.roomId, sessionId });
  await f.end(sessionId, f.uid, requestId);
  assert.equal((await f.channel.ref.get()).data().activeSessionId, next.sessionId);
});

emulatorTest("revocation closes ABA token replay and blocks new tokens until provider ACK and skew barrier", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
  await f.token(sessionId, f.uid, id);
  await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).update({ hostMuted: true, authorizationRevision: 2 });
  await reject(f.token(sessionId, f.uid, id), "permission-denied");
  await reject(f.token(sessionId), "failed-precondition");
  let release;
  f.onRevoke(() => new Promise((resolve) => { release = resolve; }));
  const pending = f.control.reconcileServerSessionParticipant({ ...f.target, roomId: f.roomId, sessionId, userId: f.uid });
  const deadline = Date.now() + 5_000;
  while (!release && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 5));
  assert.ok(release, "The revocation did not reach its provider within the bounded wait.");
  await reject(f.token(sessionId), "failed-precondition");
  release({ alreadyAbsent: false }); await pending;
  await reject(f.token(sessionId), "failed-precondition");
  f.advance(2_001);
  const current = await f.token(sessionId);
  assert.equal(current.permissions.canPublish, false);
  assert.deepEqual(current.permittedTrackSources, []);
  await reject(f.token(sessionId, f.uid, id), "permission-denied");
});

emulatorTest("orphan ending session from ownership transfer blocks starting before cleanup integration", async () => {
  const f = await fixture(); const { sessionId } = await f.start();
  await f.channel.ref.update({ activeSessionId: null });
  await db.doc(`rooms/${f.roomId}`).update({ isLive: false, voiceSessionId: null, livekitRoomName: null });
  await f.channel.ref.collection("channelSessions").doc(sessionId).update({ status: "ending" });
  await reject(f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() })), "failed-precondition");
});

emulatorTest("session lifecycle leaves free-capacity and purchased entitlements unchanged", async () => {
  const f = await fixture();
  const capacityRef = db.doc(`privateRoomHostGuards/${f.uid}`);
  const before = (await capacityRef.get()).data();
  const serverCapacityRef = db.doc(`privateServerOwnerGuards/${f.uid}`);
  const serverBefore = (await serverCapacityRef.get()).data();
  const clubCapacityRef = db.doc(`clubOwnershipGuards/${f.uid}`);
  const clubBefore = (await clubCapacityRef.get()).data();
  const entitlement = { ownerId: f.uid, source: "purchased", marker: "test-only-preserved" };
  const entitlementRef = db.doc(`entitlements/${f.uid}`);
  await entitlementRef.set(entitlement);
  const { sessionId } = await f.start(); await f.token(sessionId); await f.end(sessionId);
  assert.deepEqual((await capacityRef.get()).data(), before);
  assert.deepEqual((await serverCapacityRef.get()).data(), serverBefore);
  assert.deepEqual((await clubCapacityRef.get()).data(), clubBefore);
  assert.deepEqual((await entitlementRef.get()).data(), entitlement);
});

emulatorTest("end during signing denies the delayed token without creating a post-end recipient", async () => {
  const f = await fixture(); const { sessionId } = await f.start();
  f.onSign(() => f.end(sessionId));
  await reject(f.token(sessionId), "permission-denied");
  assert.equal((await f.channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).get()).size, 0);
  assert.equal((await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`).get()).exists, false);
});

emulatorTest("denied token probes exhaust the actor budget before any new target admission", async () => {
  const f = await fixture(); const { sessionId } = await f.start();
  for (let index = 0; index < 12; index += 1) await reject(f.token(`missing-${index}`), "permission-denied");
  await reject(f.token(sessionId), "resource-exhausted");
  assert.equal(f.calls.signed.length, 0);
  assert.equal((await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`).get()).exists, false);
});

emulatorTest("reusing a request ID for a different authorized generation is a conflict, never a cached grant", async () => {
  const f = await fixture(); const first = await f.start(); const id = randomUUID();
  await f.token(first.sessionId, f.uid, id); await f.end(first.sessionId);
  const next = await f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() }));
  await reject(f.token(next.sessionId, f.uid, id), "already-exists");
  assert.equal(f.calls.signed.length, 1);
});

emulatorTest("bounded teardown pages retain the barrier until every issued recipient and final room deletion complete", async () => {
  const f = await fixture(); const { sessionId } = await f.start();
  for (let index = 0; index < 21; index += 1) await f.token(sessionId, await f.member());
  const first = await f.end(sessionId);
  assert.equal(first.cleanupPending, true);
  assert.equal(f.calls.revoked.length, 20);
  assert.equal(f.calls.ended.length, 0);
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().serverSessionCleanupId, sessionId);
  const final = await f.control.processServerSessionEndPage({ operationId: first.operationId });
  assert.equal(final.cleanupPending, false);
  assert.equal(f.calls.revoked.length, 21);
  assert.equal(f.calls.ended.length, 1);
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().serverSessionCleanupId, null);
});

emulatorTest("a provider deletion failure remains pending and converges on the same end receipt", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  f.onEnd(() => { throw new Error("test-only provider outage"); });
  const id = randomUUID(); const initial = await f.end(sessionId, f.uid, id);
  assert.equal(initial.cleanupPending, true);
  assert.equal((await db.doc(`serverControlOutbox/${initial.operationId}`).get()).data().status, "pending");
  f.onEnd(null);
  const retried = await f.end(sessionId, f.uid, id);
  assert.equal(retried.operationId, initial.operationId);
  assert.equal(retried.cleanupPending, false);
});

emulatorTest("terminal delete sees durable positive receipts and a generation-bound checkpoint before its RPC", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  const sessionRef = f.channel.ref.collection("channelSessions").doc(sessionId);
  let observed;
  f.onEnd(async () => {
    const session = (await sessionRef.get()).data();
    const recipient = (await sessionRef.collection("tokenRecipients").doc(tokenRecipientId(f.uid)).get()).data();
    const job = (await db.doc(`serverControlOutbox/${session.endOperationId}`).get()).data();
    observed = { session, recipient, job };
    return {};
  });
  const ended = await f.end(sessionId);
  assert.ok(observed, "The authorized terminal worker must reach its provider.");
  assert.equal(observed.recipient.revocationState, "revoked", "Positive cutoff must be durable before DeleteRoom.");
  assert.ok(observed.recipient.revokedBeforeMillis > 0);
  assert.equal(observed.job.terminalDelete.version, 1);
  assert.equal(observed.job.terminalDelete.endOperationId, ended.operationId);
  assert.equal(observed.job.terminalDelete.recipientCursor, tokenRecipientId(f.uid));
  assert.equal(observed.job.terminalDelete.authorizationRevision, observed.session.authorizationRevision);
  assert.equal(observed.session.status, "ending");
  assert.equal(ended.cleanupPending, false);
});

emulatorTest("lost terminal DeleteRoom ACK retries delete-only without removing settled offline identities again", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  let remotelyDeleted = false;
  f.onRevoke(() => ({ alreadyAbsent: remotelyDeleted }));
  f.onEnd(() => {
    if (!remotelyDeleted) {
      remotelyDeleted = true;
      throw Object.assign(new Error("test-only successful remote delete with lost response"), { code: "deadline_exceeded" });
    }
    return { alreadyAbsent: true };
  });
  const requestId = randomUUID();
  const first = await f.end(sessionId, f.uid, requestId);
  assert.equal(first.cleanupPending, true);
  assert.equal(remotelyDeleted, true);
  await reject(f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() })), "failed-precondition");
  const retry = await f.end(sessionId, f.uid, requestId);
  assert.equal(retry.operationId, first.operationId);
  assert.equal(retry.cleanupPending, false, "DeleteRoom NOT_FOUND may settle only the already-checkpointed terminal delete.");
  assert.equal(f.calls.revoked.length, 1, "A durable positive cutoff must not be requested again after the room was removed.");
  assert.equal(f.calls.ended.length, 2);
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().serverSessionCleanupId, null);
});

emulatorTest("stale cleanup does not delete a newer generation mirror, roster or active room pointer", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  const oldParticipant = (await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).get()).data();
  const oldMirror = (await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`).get()).data();
  const newSessionId = "new-generation-fixture";
  const newRtc = canonicalLiveKitRoomName(f.target.serverId, f.target.channelId, newSessionId);
  f.onEnd(async () => {
    await db.doc(`rooms/${f.roomId}`).update({ isLive: true, voiceSessionId: newSessionId,
      livekitRoomName: newRtc, serverSessionCleanupId: null });
    await f.channel.ref.update({ activeSessionId: newSessionId });
    // Positive revocation now legitimately removes the old projections before
    // DeleteRoom. Recreate the replacement fixture rather than updating a
    // deleted document; the stronger real-start rollover case is below.
    await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).set({ ...oldParticipant, sessionId: newSessionId, tokenAuthorityFingerprint: "new-fingerprint" });
    await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`).set({ ...oldMirror, sessionId: newSessionId,
      livekitRoomName: newRtc, authorityFingerprint: "new-fingerprint" });
  });
  const ended = await f.end(sessionId);
  assert.equal(ended.cleanupPending, false);
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().voiceSessionId, newSessionId);
  assert.equal((await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).get()).data().sessionId, newSessionId);
  assert.equal((await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`).get()).data().sessionId, newSessionId);
});

emulatorTest("runtime end also fails closed for held and archived roots, including an old receipt", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
  await f.end(sessionId, f.uid, id);
  for (const patch of [{ status: "preparing", serverActivationState: "held" },
    { status: "archived", serverActivationState: "active" }, { status: "active", serverSchemaVersion: 2 }]) {
    await db.doc(`clubs/${f.target.serverId}`).update(patch);
    await reject(f.end(sessionId, f.uid, id), "permission-denied");
  }
});

emulatorTest("communication sanctions do not trap an authorized host in a running session", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  await db.doc(`restrictions/${f.uid}`).set({ type: "communicationMute", expiresAt: null });
  await reject(f.token(sessionId), "permission-denied");
  const response = await f.service.endServerChannelSessionV1({ auth: { uid: f.uid, token: {} },
    data: { ...f.target, sessionId, requestId: randomUUID() } });
  assert.equal(response.cleanupPending, false);
});

emulatorTest("metadata rename and channel reordering do not revoke unchanged media authority", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); const id = randomUUID();
  const prior = await f.token(sessionId, f.uid, id);
  await f.channel.ref.update({ name: "Renamed media", position: 99, revision: 10 });
  await db.doc(`clubs/${f.target.serverId}`).update({ name: "Renamed server", revision: 12 });
  await db.doc(`users/${f.uid}`).update({ displayName: "Renamed person" });
  assert.deepEqual(await f.token(sessionId, f.uid, id), prior);
  const fresh = await f.token(sessionId);
  assert.equal(fresh.participantName, "Renamed person");
  assert.deepEqual(fresh.permittedTrackSources, prior.permittedTrackSources);
  assert.equal(f.calls.revoked.length, 0);
});

emulatorTest("duplicate reconciliation is single-flight; expired lease never reclaims an unresolved removal", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).update({ hostMuted: true, authorizationRevision: 2 });
  const input = { ...f.target, roomId: f.roomId, sessionId, userId: f.uid };
  const recipientRef = f.channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).doc(tokenRecipientId(f.uid));
  const entered = gate(); const release = gate();
  f.onRevoke(async () => { entered.resolve(); await release.promise; return { alreadyAbsent: false }; });
  const first = f.control.reconcileServerSessionParticipant(input);
  await entered.promise;
  try {
    const attempt = (await recipientRef.get()).data().revocationAttempt;
    const second = await f.control.reconcileServerSessionParticipant(input);
    assert.deepEqual(second, { revocationPending: true, revoked: false, recoveryRequired: false });
    assert.equal(f.calls.revoked.length, 1);
    f.advance(attempt.leaseExpiresAtMillis - f.clock());
    const expired = await f.control.reconcileServerSessionParticipant(input);
    assert.deepEqual(expired, { revocationPending: true, revoked: false, recoveryRequired: true });
    assert.equal(f.calls.revoked.length, 1);
    assert.equal((await recipientRef.get()).data().revocationAttempt.id, attempt.id);
    await reject(f.token(sessionId), "failed-precondition");
    release.resolve(); assert.equal((await first).revoked, true);
    const acknowledged = (await recipientRef.get()).data();
    assert.equal(acknowledged.revocationAttempt.state, "acknowledged");
    assert.equal(acknowledged.revocationAttempt.id, attempt.id);
    f.advance(acknowledged.reconnectAfterMillis - f.clock() - 1);
    await reject(f.token(sessionId), "failed-precondition");
    f.advance(1);
    assert.equal((await f.token(sessionId)).permissions.canPublish, false);
  } finally { release.resolve(); await Promise.allSettled([first]); }
});

emulatorTest("uncertain removal cannot retry or admit after expiry; authorized whole-generation end recovers", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).update({ hostMuted: true, authorizationRevision: 2 });
  const input = { ...f.target, roomId: f.roomId, sessionId, userId: f.uid };
  const recipientRef = f.channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).doc(tokenRecipientId(f.uid));
  f.onRevoke(() => { throw Object.assign(new Error("test-only lost response"), { code: "deadline_exceeded" }); });
  await assert.rejects(f.control.reconcileServerSessionParticipant(input));
  const uncertain = (await recipientRef.get()).data();
  assert.equal(uncertain.revocationState, "revoking");
  assert.equal(uncertain.revocationAttempt.state, "uncertain");
  f.advance(1_000_000);
  f.onRevoke(null);
  const retried = await f.control.reconcileServerSessionParticipant(input);
  assert.equal(retried.recoveryRequired, true);
  assert.equal(f.calls.revoked.length, 1);
  await reject(f.token(sessionId), "failed-precondition");
  assert.equal((await f.end(sessionId)).cleanupPending, false);
  const next = await f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() }));
  const connection = await f.token(next.sessionId);
  assert.notEqual(next.sessionId, sessionId);
  assert.notEqual(connection.roomName, uncertain.livekitRoomName);
  const oldReceipt = (await recipientRef.get()).data();
  assert.equal(oldReceipt.revocationState, "revoked");
  assert.deepEqual(oldReceipt.revocationAttempt, uncertain.revocationAttempt);
  const currentPaths = [db.doc(`rooms/${f.roomId}`), db.doc(`rooms/${f.roomId}/participants/${f.uid}`),
    db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`),
    f.channel.ref.collection(`channelSessions/${next.sessionId}/tokenRecipients`).doc(tokenRecipientId(f.uid))];
  const currentBefore = await Promise.all(currentPaths.map(async (ref) => (await ref.get()).data()));
  const revocationsBefore = f.calls.revoked.length;
  for (let retry = 0; retry < 2; retry += 1) {
    assert.deepEqual(await f.control.reconcileServerSessionParticipant(input),
      { revocationPending: false, revoked: false });
  }
  assert.equal(f.calls.revoked.length, revocationsBefore);
  assert.deepEqual((await recipientRef.get()).data(), oldReceipt);
  assert.deepEqual(await Promise.all(currentPaths.map(async (ref) => (await ref.get()).data())), currentBefore);
  await reject(f.token(sessionId), "permission-denied");
});

emulatorTest("only the durable attempt owner may acknowledge a removal and release admission", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).update({ hostMuted: true, authorizationRevision: 2 });
  const input = { ...f.target, roomId: f.roomId, sessionId, userId: f.uid };
  const recipientRef = f.channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).doc(tokenRecipientId(f.uid));
  const differentOwner = randomUUID();
  f.onRevoke(async () => {
    // A server-side corruption/race fixture, never an owner-written field.
    await recipientRef.update({ "revocationAttempt.id": differentOwner });
    return { alreadyAbsent: false };
  });
  const result = await f.control.reconcileServerSessionParticipant(input);
  assert.equal(result.revocationPending, true);
  assert.equal(result.revoked, false);
  assert.equal((await recipientRef.get()).data().revocationAttempt.id, differentOwner);
  f.advance(120_001);
  await reject(f.token(sessionId), "failed-precondition");
  assert.equal((await f.control.reconcileServerSessionParticipant(input)).recoveryRequired, true);
  assert.equal(f.calls.revoked.length, 1);
});

emulatorTest("late ACK after expired-attempt generation rollover cannot mutate the new recipient or mirrors", async () => {
  const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
  await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).update({ hostMuted: true, authorizationRevision: 2 });
  const input = { ...f.target, roomId: f.roomId, sessionId, userId: f.uid };
  const entered = gate(); const release = gate();
  f.onRevoke(async () => { entered.resolve(); await release.promise; return { alreadyAbsent: false }; });
  const old = f.control.reconcileServerSessionParticipant(input);
  await entered.promise;
  try {
    f.advance(120_001);
    assert.equal((await f.control.reconcileServerSessionParticipant(input)).recoveryRequired, true);
    f.onRevoke(null);
    assert.equal((await f.end(sessionId)).cleanupPending, false);
    const next = await f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() }));
    await f.token(next.sessionId);
    const paths = [db.doc(`rooms/${f.roomId}`), db.doc(`rooms/${f.roomId}/participants/${f.uid}`),
      db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`),
      f.channel.ref.collection(`channelSessions/${next.sessionId}/tokenRecipients`).doc(tokenRecipientId(f.uid))];
    const before = await Promise.all(paths.map(async (ref) => (await ref.get()).data()));
    release.resolve(); assert.equal((await old).revoked, false);
    const after = await Promise.all(paths.map(async (ref) => (await ref.get()).data()));
    assert.deepEqual(after, before);
  } finally { release.resolve(); await Promise.allSettled([old]); }
});

for (const count of [0, 19, 20, 21]) emulatorTest(`terminal SDK budget for ${count} issued identities is at most twenty RPCs per invocation`, async () => {
  let inFlight = 0; let maximumInFlight = 0;
  const calls = []; const checkpoints = [];
  let f;
  const adapter = createServerLiveKitAdapter({ apiKey: () => "test-key", apiSecret: () => "test-secret",
    serverUrl: () => "wss://test-fixture.livekit.cloud", client: {
      async removeParticipant(room, identity) {
        calls.push({ kind: "remove", room, identity }); inFlight += 1;
        maximumInFlight = Math.max(maximumInFlight, inFlight);
        try { await new Promise((resolve) => setTimeout(resolve, 2)); }
        finally { inFlight -= 1; }
      },
      async deleteRoom(room) {
        calls.push({ kind: "delete", room }); assert.equal(inFlight, 0);
        const sessions = await f.channel.ref.collection("channelSessions").get();
        const session = sessions.docs[0];
        const recipients = await session.ref.collection("tokenRecipients").get();
        assert.equal(recipients.size, count);
        for (const recipient of recipients.docs) {
          assert.equal(recipient.data().revocationState, "revoked");
          assert.ok(recipient.data().revokedBeforeMillis > 0);
        }
        checkpoints.push((await db.doc(`serverControlOutbox/${session.data().endOperationId}`).get()).data().terminalDelete);
      },
      async listParticipants() { assert.fail("Terminal cleanup must not enumerate the provider roster."); },
      async getParticipant() { assert.fail("Terminal cleanup must not inspect the provider roster."); },
    } });
  f = await fixture({ controlAdapter: adapter }); const { sessionId } = await f.start();
  for (let index = 0; index < count; index += 1) {
    const member = await f.member(); await f.token(sessionId, member);
    // The issued credential remains even when its owner never goes online.
    await db.doc(`rooms/${f.roomId}/participants/${member}`).delete();
  }
  let before = calls.length;
  let result = await f.end(sessionId);
  assert.ok(calls.length - before <= 20);
  if (count >= 20) {
    assert.equal(result.cleanupPending, true);
    assert.equal(calls.length, 20);
    assert.equal(calls.filter((call) => call.kind === "delete").length, 0);
    const job = (await db.doc(`serverControlOutbox/${result.operationId}`).get()).data();
    assert.equal(Object.hasOwn(job, "terminalDelete"), count === 20);
    assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().serverSessionCleanupId, sessionId);
    before = calls.length;
    result = await f.control.processServerSessionEndPage({ operationId: result.operationId });
    assert.ok(calls.length - before <= 20);
    assert.equal(calls.length - before, count === 20 ? 1 : 2);
  }
  assert.equal(result.cleanupPending, false);
  assert.equal(calls.filter((call) => call.kind === "remove").length, count);
  assert.equal(calls.filter((call) => call.kind === "delete").length, 1);
  assert.equal(checkpoints.length, 1); assert.equal(checkpoints[0].version, 1);
  assert.ok(maximumInFlight <= 4);
  if (count >= 4) assert.equal(maximumInFlight, 4);
  assert.ok(calls.every((call) => call.room === canonicalLiveKitRoomName(f.target.serverId, f.target.channelId, sessionId)));
});

emulatorTest("a committed receipt checkpoint survives loss before DeleteRoom dispatch and retries delete-only", async () => {
  let loseCheckpointAck = false;
  const hooks = { afterTransaction(writes) {
    if (loseCheckpointAck && writes.some((write) => write.patch.terminalDelete?.version === 1)) {
      loseCheckpointAck = false;
      throw new Error("test-only process loss after receipt commit, before terminal dispatch");
    }
  } };
  const f = await fixture({ runtimeDb: databaseWithTransactionFaults(hooks) });
  const { sessionId } = await f.start(); await f.token(sessionId);
  loseCheckpointAck = true;
  const id = randomUUID(); const pending = await f.end(sessionId, f.uid, id);
  const job = (await db.doc(`serverControlOutbox/${pending.operationId}`).get()).data();
  assert.equal(pending.cleanupPending, true); assert.equal(job.terminalDelete.version, 1);
  assert.equal(job.cursor, tokenRecipientId(f.uid)); assert.equal(f.calls.revoked.length, 1);
  assert.equal(f.calls.ended.length, 0);
  f.onRevoke(() => { assert.fail("A ready checkpoint must not repeat any settled participant removal."); });
  const retry = await f.end(sessionId, f.uid, id);
  assert.equal(retry.operationId, pending.operationId); assert.equal(retry.cleanupPending, false);
  assert.equal(f.calls.revoked.length, 1); assert.equal(f.calls.ended.length, 1);
});

emulatorTest("a successful DeleteRoom followed by failed final commit retries only terminal absence", async () => {
  let failNextTransaction = false;
  const hooks = { beforeTransaction() {
    if (failNextTransaction) { failNextTransaction = false; throw new Error("test-only final commit unavailable"); }
  } };
  const f = await fixture({ runtimeDb: databaseWithTransactionFaults(hooks) });
  const { sessionId } = await f.start(); await f.token(sessionId);
  let remotelyDeleted = false;
  f.onEnd(() => {
    if (!remotelyDeleted) {
      remotelyDeleted = true; failNextTransaction = true;
      return { alreadyAbsent: false };
    }
    return { alreadyAbsent: true };
  });
  const id = randomUUID(); const pending = await f.end(sessionId, f.uid, id);
  assert.equal(pending.cleanupPending, true);
  const reference = db.doc(`serverControlOutbox/${pending.operationId}`);
  const checkpoint = (await reference.get()).data().terminalDelete;
  assert.equal(checkpoint.version, 1);
  assert.equal((await f.channel.ref.collection("channelSessions").doc(sessionId).get()).data().status, "ending");
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().serverSessionCleanupId, sessionId);
  f.onRevoke(() => ({ alreadyAbsent: true }));
  assert.equal((await f.end(sessionId, f.uid, id)).cleanupPending, false);
  assert.equal(f.calls.revoked.length, 1); assert.equal(f.calls.ended.length, 2);
  assert.deepEqual((await reference.get()).data().terminalDelete, checkpoint);
});

emulatorTest("partial terminal failure awaits every started RPC and never commits a checkpoint or cursor", async () => {
  const f = await fixture(); const { sessionId } = await f.start();
  const members = [await f.member(), await f.member(), await f.member(), await f.member(), await f.member()];
  for (const member of members) await f.token(sessionId, member);
  const release = gate(); const entered = gate(); let started = 0; let settled = false;
  f.onRevoke(async () => {
    started += 1;
    if (started === 4) entered.resolve();
    if (started === 1) throw new Error("test-only first participant removal failed");
    await release.promise;
    return { alreadyAbsent: false };
  });
  const end = f.end(sessionId).then((value) => { settled = true; return value; });
  await entered.promise;
  try {
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(settled, false, "A failed first RPC must not abandon the other started provider calls.");
    assert.equal(started, 4, "No later batch may start after a page failure.");
    release.resolve();
    const pending = await end;
    assert.equal(pending.cleanupPending, true); assert.equal(f.calls.ended.length, 0);
    const job = (await db.doc(`serverControlOutbox/${pending.operationId}`).get()).data();
    assert.equal(job.cursor, null); assert.equal(Object.hasOwn(job, "terminalDelete"), false);
    assert.equal(job.leaseId, null);
    const recipients = await f.channel.ref.collection(`channelSessions/${sessionId}/tokenRecipients`).get();
    assert.ok(recipients.docs.every((doc) => doc.data().revocationState === "revoking"));
  } finally { release.resolve(); await Promise.allSettled([end]); }
});

emulatorTest("late token signing cannot append an identity after the terminal checkpoint's empty scan", async () => {
  const f = await fixture(); const { sessionId } = await f.start();
  const signEntered = gate(); const signRelease = gate(); const deleteEntered = gate(); const deleteRelease = gate();
  f.onSign(async () => { signEntered.resolve(); await signRelease.promise; });
  f.onEnd(async () => { deleteEntered.resolve(); await deleteRelease.promise; return {}; });
  const issuance = f.token(sessionId); await signEntered.promise;
  const closing = f.end(sessionId); await deleteEntered.promise;
  try {
    const sessionRef = f.channel.ref.collection("channelSessions").doc(sessionId);
    const session = (await sessionRef.get()).data();
    const checkpoint = (await db.doc(`serverControlOutbox/${session.endOperationId}`).get()).data().terminalDelete;
    assert.equal(checkpoint.version, 1); assert.equal(checkpoint.recipientCursor, null);
    signRelease.resolve(); await reject(issuance, "permission-denied");
    assert.equal((await sessionRef.collection("tokenRecipients").get()).size, 0);
    assert.equal((await db.doc(`rooms/${f.roomId}/participants/${f.uid}`).get()).exists, false);
    assert.equal((await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`).get()).exists, false);
    deleteRelease.resolve(); assert.equal((await closing).cleanupPending, false);
    assert.equal((await sessionRef.collection("tokenRecipients").get()).size, 0);
  } finally { signRelease.resolve(); deleteRelease.resolve(); await Promise.allSettled([issuance, closing]); }
});

emulatorTest("checkpoint validation denies unknown fields, mismatched scope and invalid or nonterminal cursors before RPC", async () => {
  const f = await fixture(); const { sessionId } = await f.start();
  await f.token(sessionId); await f.token(sessionId, await f.member());
  f.onEnd(() => { throw new Error("test-only deletion pause"); });
  const pending = await f.end(sessionId);
  const jobRef = db.doc(`serverControlOutbox/${pending.operationId}`);
  const original = (await jobRef.get()).data(); const marker = original.terminalDelete;
  const sessionRef = f.channel.ref.collection("channelSessions").doc(sessionId);
  const session = (await sessionRef.get()).data();
  const binding = { ...f.target, roomId: f.roomId, sessionId, livekitRoomName: original.livekitRoomName };
  const recipients = (await sessionRef.collection("tokenRecipients").get()).docs.sort((a, b) => a.id.localeCompare(b.id));
  const withCursor = (cursor) => ({ ...original, cursor, terminalDelete: { ...marker, recipientCursor: cursor,
    bindingFingerprint: digest("server.session.terminal.delete.v1", binding, original.operationId, session.authorizationRevision, cursor) } });
  for (const mutation of [
    { ...original, terminalDelete: null },
    { ...original, terminalDelete: { ...marker, version: 2 } },
    { ...original, terminalDelete: { ...marker, phase: "completed" } },
    { ...original, terminalDelete: { ...marker, readyAt: "invalid" } },
    { ...original, terminalDelete: { ...marker, endOperationId: "other-end" } },
    { ...original, terminalDelete: { ...marker, authorizationRevision: marker.authorizationRevision + 1 } },
    { ...original, terminalDelete: { ...marker, bindingFingerprint: "0".repeat(64) } },
    { ...original, cursor: "../foreign" },
    { ...original, cursor: null },
    { ...original, sessionId: "foreign-generation" },
    { ...original, status: "completed" },
    withCursor("f".repeat(64)),
    withCursor(recipients[0].id), // Valid cursor document, but the tail is not empty.
  ]) {
    await jobRef.set(mutation);
    await assert.rejects(f.control.processServerSessionEndPage({ operationId: original.operationId }));
    assert.equal(f.calls.revoked.length, 2); assert.equal(f.calls.ended.length, 1);
    assert.equal((await sessionRef.get()).data().status, "ending");
    assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().serverSessionCleanupId, sessionId);
  }
  await jobRef.set(original);
  const lastRef = sessionRef.collection("tokenRecipients").doc(original.cursor);
  const last = (await lastRef.get()).data();
  for (const patch of [{ revocationState: "active" }, { revokedBeforeMillis: null }, { sessionId: "foreign" }]) {
    await lastRef.set({ ...last, ...patch });
    await assert.rejects(f.control.processServerSessionEndPage({ operationId: original.operationId }));
    assert.equal(f.calls.ended.length, 1); assert.equal(f.calls.revoked.length, 2);
  }
  await lastRef.set(last); f.onEnd(null);
  assert.equal((await f.control.processServerSessionEndPage({ operationId: original.operationId })).cleanupPending, false);
});

emulatorTest("receipt commit rechecks the original cursor, end operation, binding, revision and owned lease", async () => {
  for (const change of ["cursor", "operation", "binding", "revision", "lease"]) {
    const f = await fixture(); const { sessionId } = await f.start(); await f.token(sessionId);
    const sessionRef = f.channel.ref.collection("channelSessions").doc(sessionId);
    f.onRevoke(async () => {
      const session = (await sessionRef.get()).data(); const jobRef = db.doc(`serverControlOutbox/${session.endOperationId}`);
      if (change === "cursor") await jobRef.update({ cursor: "f".repeat(64) });
      if (change === "operation") await sessionRef.update({ endOperationId: "foreign-end" });
      if (change === "binding") await jobRef.update({ roomId: "foreign-anchor" });
      if (change === "revision") await sessionRef.update({ authorizationRevision: session.authorizationRevision + 1 });
      if (change === "lease") await jobRef.update({ leaseId: randomUUID(), leaseExpiresAtMillis: f.clock() + 120_000 });
      return { alreadyAbsent: false };
    });
    const pending = await f.end(sessionId);
    assert.equal(pending.cleanupPending, true, change);
    assert.equal(f.calls.ended.length, 0, change);
    assert.equal(Object.hasOwn((await db.doc(`serverControlOutbox/${pending.operationId}`).get()).data(), "terminalDelete"), false, change);
  }
});

for (const lateOutcome of ["success", "failure"]) emulatorTest(`late terminal lease ${lateOutcome} cannot change a genuinely started next generation`, async () => {
  const f = await fixture(); const old = await f.start(); const oldToken = await f.token(old.sessionId);
  f.onEnd(() => { throw new Error("test-only first terminal outage"); });
  const pending = await f.end(old.sessionId);
  const entered = gate(); const release = gate();
  f.onEnd(async () => {
    entered.resolve(); await release.promise;
    if (lateOutcome === "failure") throw new Error("test-only late terminal failure");
    return {};
  });
  const late = f.control.processServerSessionEndPage({ operationId: pending.operationId });
  await entered.promise;
  try {
    f.advance(120_001); f.onEnd(null);
    assert.equal((await f.control.processServerSessionEndPage({ operationId: pending.operationId })).cleanupPending, false);
    const next = await f.service.startServerChannelSessionV1(request(f.uid, { ...f.startData, requestId: randomUUID() }));
    const nextToken = await f.token(next.sessionId);
    assert.notEqual(nextToken.roomName, oldToken.roomName);
    const paths = [db.doc(`rooms/${f.roomId}`), f.channel.ref,
      db.doc(`rooms/${f.roomId}/participants/${f.uid}`), db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.roomId}`),
      f.channel.ref.collection(`channelSessions/${next.sessionId}/tokenRecipients`).doc(tokenRecipientId(f.uid)),
      db.doc(`serverControlOutbox/${pending.operationId}`)];
    const before = await Promise.all(paths.map(async (reference) => (await reference.get()).data()));
    release.resolve();
    if (lateOutcome === "failure") await assert.rejects(late); else await late;
    assert.deepEqual(await Promise.all(paths.map(async (reference) => (await reference.get()).data())), before);
    assert.equal(f.calls.revoked.length, 1);
    assert.ok(f.calls.ended.every((name) => name === oldToken.roomName));
  } finally { release.resolve(); await Promise.allSettled([late]); }
});

// ADR-A: the client-visible liveness projection. These assert the honest
// shape as much as the transitions — a count is never written, because token
// admission is not provider-connected presence (gap G6).
emulatorTest("start and end project liveness onto the channel, with a start instant and no participant count", async () => {
  const f = await fixture();
  const seeded = (await f.channel.ref.get()).data().liveness;
  assert.deepEqual(Object.keys(seeded).sort(), ["isLive", "schemaVersion", "startedAt"]);
  assert.deepEqual(seeded, { schemaVersion: 1, isLive: false, startedAt: null });
  const { sessionId } = await f.start();
  const started = (await f.channel.ref.get()).data();
  const session = (await f.channel.ref.collection("channelSessions").doc(sessionId).get()).data();
  assert.equal(started.liveness.isLive, true);
  assert.equal(started.liveness.startedAt.toMillis(), session.startedAt.toMillis());
  assert.equal(Object.hasOwn(started.liveness, "participantCount"), false);
  // Admitting people changes no count, on the channel or on the anchor.
  await f.token(sessionId, await f.member());
  await f.token(sessionId, await f.member());
  assert.deepEqual((await f.channel.ref.get()).data().liveness, started.liveness);
  assert.equal((await db.doc(`rooms/${f.roomId}`).get()).data().participantCount, 0);
  await f.end(sessionId);
  assert.deepEqual((await f.channel.ref.get()).data().liveness, { schemaVersion: 1, isLive: false, startedAt: null });
  assert.equal((await f.channel.ref.get()).data().activeSessionId, null);
});

emulatorTest("archiving or deleting a live channel retires its projection with the generation", async () => {
  for (const archive of [true, false]) {
    const f = await fixture();
    await f.start();
    assert.equal((await f.channel.ref.get()).data().liveness.isLive, true);
    const data = { serverId: f.target.serverId, channelId: f.target.channelId, requestId: randomUUID() };
    await (archive
      ? f.channelService.archiveServerChannelV1(request(f.uid, data))
      : f.channelService.deleteServerChannelV1(request(f.uid, data)));
    const channel = (await f.channel.ref.get()).data();
    assert.equal(channel.status, archive ? "archived" : "deleting");
    assert.equal(channel.activeSessionId, null);
    assert.deepEqual(channel.liveness, { schemaVersion: 1, isLive: false, startedAt: null });
  }
});

emulatorTest("terminal cleanup retires a projection stranded live once no generation claims it", async () => {
  const f = await fixture();
  const { sessionId } = await f.start();
  await f.token(sessionId);
  f.onRevoke(() => ({ alreadyAbsent: true }));
  const requestId = randomUUID();
  assert.equal((await f.end(sessionId, f.uid, requestId)).cleanupPending, true);
  // The authorized end already retired it; strand it the way an interrupted
  // writer would, with no generation named by the channel any more.
  assert.equal((await f.channel.ref.get()).data().liveness.isLive, false);
  await f.channel.ref.update({ liveness: { schemaVersion: 1, isLive: true, startedAt: Timestamp.fromMillis(f.clock()) } });
  f.onRevoke(null);
  assert.equal((await f.end(sessionId, f.uid, requestId)).cleanupPending, false);
  const channel = (await f.channel.ref.get()).data();
  assert.equal(channel.activeSessionId, null);
  assert.deepEqual(channel.liveness, { schemaVersion: 1, isLive: false, startedAt: null });
});

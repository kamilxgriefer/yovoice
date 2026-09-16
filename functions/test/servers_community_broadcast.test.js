const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { after, test } = require('node:test');

const { createServerCreationService } = require('../servers/creation');
const { createServerSessionService } = require('../servers/sessions');
const { createServerSessionControlService } = require('../servers/session_control');
const {
  createServerCommunityBroadcastService,
} = require('../servers/community_broadcast');
const { createServerBroadcastCleanupService } = require('../servers/community_broadcast_cleanup');
const {
  COMMUNITY_BROADCAST_GLOBAL_CAP,
  COMMUNITY_BROADCAST_RATE_SCOPE,
  broadcastCapacityReference,
  broadcastSlotBinding,
  broadcastUsageReference,
  communityBroadcastBinding,
  communityBroadcastInput,
  communityBroadcastMetadata,
} = require('../servers/community_broadcast_contract');
const { stageConvergenceSessionEnd } = require('../servers/convergence_lifecycle');
const { createServerManagementService } = require('../servers/management');
const { createServerLiveKitAdapter } = require('../servers/session_livekit');
const { SESSION_TOKEN_TTL_SECONDS } = require('../servers/session_contract');
const { rateLimitReference } = require('../integrity/guards');

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost ?? '');
let db; let app; let Timestamp;
if (enabled) {
  const admin = require('firebase-admin/app');
  const firestore = require('firebase-admin/firestore');
  Timestamp = firestore.Timestamp;
  app = admin.initializeApp({ projectId: 'demo-yovoice-community-broadcast' });
  db = firestore.getFirestore(app);
}
after(async () => { if (app) await require('firebase-admin/app').deleteApp(app); });
const emulatorTest = (name, fn) => test(name, {
  skip: enabled ? false : 'Requires explicit localhost demo Firestore emulator.',
  timeout: 45_000,
}, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
const reject = (promise, code) => assert.rejects(promise, (error) => error.code === code);

test('OBS input accepts only the exact generation and retry identity', () => {
  const value = { serverId: 'server', channelId: 'stage', sessionId: 'session', requestId: 'request-0001' };
  assert.deepEqual(communityBroadcastInput(value), value);
  for (const patch of [{ roomId: 'chosen' }, { hostId: 'chosen' }, { role: 'host' },
    { inputType: 'WHIP' }, { requestId: 'short' }, { sessionId: '../bad' }]) {
    assert.throws(() => communityBroadcastInput({ ...value, ...patch }),
      (error) => error.code === 'invalid-argument');
  }
});

test('LiveKit adapter creates one metadata-bound RTMP input and deletes it before the room', async () => {
  const sdk = require('livekit-server-sdk');
  const calls = [];
  let rows = [];
  const roomClient = { async deleteRoom(room) { calls.push(['deleteRoom', room]); } };
  const ingressClient = {
    async listIngress(options) { calls.push(['listIngress', options]); return rows; },
    async createIngress(inputType, options) {
      calls.push(['createIngress', inputType, options]);
      const result = { ingressId: 'ingress_12345678', inputType, streamKey: 'private-key-12345678',
        url: 'rtmps://ingress.example.test/live', roomName: options.roomName,
        participantIdentity: options.participantIdentity, participantMetadata: options.participantMetadata };
      rows = [result];
      return result;
    },
    async deleteIngress(id) { calls.push(['deleteIngress', id]); rows = []; },
  };
  const adapter = createServerLiveKitAdapter({
    apiKey: () => 'key', apiSecret: () => 'secret',
    serverUrl: () => 'wss://test-fixture.livekit.cloud',
    client: roomClient, ingressClient,
  });
  const binding = communityBroadcastBinding({ serverId: 'server', channelId: 'stage', sessionId: 'session' },
    { roomId: 'room', hostId: 'owner' });
  const first = await adapter.ensureBroadcastIngress(binding);
  assert.equal(first.created, true);
  assert.equal(first.streamKey, 'private-key-12345678');
  assert.equal(calls.filter(([name]) => name === 'createIngress').length, 1);
  const creation = calls.find(([name]) => name === 'createIngress');
  assert.equal(creation[1], sdk.IngressInput.RTMP_INPUT);
  assert.equal(creation[2].enableTranscoding, true);
  assert.deepEqual(creation[2].audio,
    { name: 'OBS audio', source: sdk.TrackSource.SCREEN_SHARE_AUDIO });
  assert.deepEqual(creation[2].video,
    { name: 'OBS screen', source: sdk.TrackSource.SCREEN_SHARE });
  assert.equal(creation[2].participantMetadata, communityBroadcastMetadata(binding));
  const replay = await adapter.ensureBroadcastIngress(binding);
  assert.equal(replay.created, false);
  assert.equal(calls.filter(([name]) => name === 'createIngress').length, 1);
  await adapter.endRoom(binding.livekitRoomName, {
    version: 1, endOperationId: 'operation', serverId: binding.serverId,
    channelId: binding.channelId, roomId: binding.roomId, sessionId: binding.sessionId,
    livekitRoomName: binding.livekitRoomName, hostId: binding.hostId,
  });
  assert.deepEqual(calls.slice(-3).map(([name]) => name), ['listIngress', 'deleteIngress', 'deleteRoom']);
});

test('an ingress lookup failure can never become a false successful room deletion', async () => {
  const calls = [];
  const binding = communityBroadcastBinding({ serverId: 'server', channelId: 'stage', sessionId: 'session' },
    { roomId: 'room', hostId: 'owner' });
  const adapter = createServerLiveKitAdapter({
    apiKey: () => 'key', apiSecret: () => 'secret', serverUrl: () => 'wss://test-fixture.livekit.cloud',
    client: { async deleteRoom() { calls.push('deleteRoom'); } },
    ingressClient: { async listIngress() {
      calls.push('listIngress');
      throw Object.assign(new Error('test-only missing ingress response'), { code: 'not_found' });
    } },
  });
  await assert.rejects(adapter.endRoom(binding.livekitRoomName, {
    version: 1, endOperationId: 'operation', serverId: binding.serverId,
    channelId: binding.channelId, roomId: binding.roomId, sessionId: binding.sessionId,
    livekitRoomName: binding.livekitRoomName, hostId: binding.hostId,
  }), (error) => error.code === 'not_found');
  assert.deepEqual(calls, ['listIngress']);
});

test('alternate terminal lifecycle stages the end during an in-flight OBS provider create', () => {
  const writes = [];
  const transaction = {
    update(reference, value) { writes.push(['update', reference, value]); },
    create(reference, value) { writes.push(['create', reference, value]); },
  };
  const dbFixture = { doc: (path) => ({ path }) };
  const now = { toMillis: () => 10_000 };
  const binding = {
    serverId: 'server', channelId: 'stage', roomId: 'room', sessionId: 'session',
    livekitRoomName: 'srv_server_stage_session',
  };
  const item = {
    sessionReference: { path: 'clubs/server/channels/stage/channelSessions/session' },
    session: {
      sessionId: 'session', status: 'live', startedById: 'owner', authorizationRevision: 1,
      maxTokenExpiresAtMillis: 20_000,
      obsIngressProvisioning: {
        schemaVersion: 2, operationId: 'a'.repeat(64), leaseId: 'lease-1234',
        startedAtMillis: 9_000, leaseExpiresAtMillis: 11_000,
      },
    },
    binding,
  };

  // A host-held provisioning lease must never delay an archive, delete,
  // transfer, staleness or staff end. The durable job instead tells the
  // terminal worker to wait for the lease and reconcile metadata-bound input.
  const ending = stageConvergenceSessionEnd({
    db: dbFixture, transaction, item, identity: { id: 'archive-operation' }, now,
  });
  assert.equal(ending.target.endOperationId.length, 64);
  const job = writes.find(([kind]) => kind === 'create')[2];
  assert.equal(job.hostId, 'owner');
  assert.equal(job.obsIngressId, null);
  assert.equal(job.reconcileObsIngress, true);
  const sessionUpdate = writes.find(([kind]) => kind === 'update')[2];
  assert.equal(sessionUpdate.status, 'ending');

  writes.length = 0;
  item.session.obsIngressProvisioning = null;
  stageConvergenceSessionEnd({
    db: dbFixture, transaction, item, identity: { id: 'archive-operation' }, now,
  });
  assert.equal(writes.find(([kind]) => kind === 'create')[2].reconcileObsIngress, false);
});

test('LiveKit adapter replaces only an exact bound input when listed credentials are unavailable', async () => {
  const sdk = require('livekit-server-sdk');
  const calls = [];
  const binding = communityBroadcastBinding({ serverId: 'server', channelId: 'stage', sessionId: 'session' },
    { roomId: 'room', hostId: 'owner' });
  let rows = [{ ingressId: 'ingress_stale', inputType: sdk.IngressInput.RTMP_INPUT,
    streamKey: '', url: '', roomName: binding.livekitRoomName,
    participantIdentity: binding.participantIdentity, participantMetadata: communityBroadcastMetadata(binding) }];
  const adapter = createServerLiveKitAdapter({
    apiKey: () => 'key', apiSecret: () => 'secret', serverUrl: () => 'wss://test-fixture.livekit.cloud',
    client: {}, ingressClient: {
      async listIngress() { return rows; },
      async deleteIngress(id) { calls.push(['deleteIngress', id]); rows = []; },
      async createIngress(inputType, options) {
        calls.push(['createIngress', inputType]);
        return { ingressId: 'ingress_recovered', inputType, streamKey: 'recovered-key-123',
          url: 'rtmps://ingress.example.test/live', roomName: options.roomName,
          participantIdentity: options.participantIdentity, participantMetadata: options.participantMetadata };
      },
    },
  });
  const receipt = await adapter.ensureBroadcastIngress(binding);
  assert.equal(receipt.ingressId, 'ingress_recovered');
  assert.equal(receipt.streamKey, 'recovered-key-123');
  assert.deepEqual(calls, [['deleteIngress', 'ingress_stale'], ['createIngress', sdk.IngressInput.RTMP_INPUT]]);
});

test('LiveKit adapter collapses exact duplicate inputs before returning one usable Stream Key', async () => {
  const sdk = require('livekit-server-sdk');
  const calls = [];
  const binding = communityBroadcastBinding({ serverId: 'server', channelId: 'stage', sessionId: 'session' },
    { roomId: 'room', hostId: 'owner' });
  const metadata = communityBroadcastMetadata(binding);
  let rows = [
    { ingressId: 'ingress_without_credentials', inputType: sdk.IngressInput.RTMP_INPUT,
      streamKey: '', url: '', roomName: binding.livekitRoomName,
      participantIdentity: binding.participantIdentity, participantMetadata: metadata },
    { ingressId: 'ingress_with_credentials', inputType: sdk.IngressInput.RTMP_INPUT,
      streamKey: 'usable-secret-key', url: 'rtmps://ingress.example.test/live',
      roomName: binding.livekitRoomName, participantIdentity: binding.participantIdentity,
      participantMetadata: metadata },
  ];
  const adapter = createServerLiveKitAdapter({
    apiKey: () => 'key', apiSecret: () => 'secret', serverUrl: () => 'wss://test-fixture.livekit.cloud',
    client: {}, ingressClient: {
      async listIngress() { return rows; },
      async deleteIngress(id) {
        calls.push(['deleteIngress', id]);
        rows = rows.filter((row) => row.ingressId !== id);
      },
      async createIngress() { calls.push(['createIngress']); throw new Error('must not create'); },
    },
  });

  const receipt = await adapter.ensureBroadcastIngress(binding);
  assert.equal(receipt.ingressId, 'ingress_with_credentials');
  assert.equal(receipt.streamKey, 'usable-secret-key');
  assert.deepEqual(calls, [['deleteIngress', 'ingress_without_credentials']]);
});

async function fixture({ moderatorHost = false } = {}) {
  const ownerUid = `broadcast-owner-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await broadcastCapacityReference(db).set({
    schemaVersion: 1, enabled: true, activeCount: 0,
    limit: COMMUNITY_BROADCAST_GLOBAL_CAP, updatedAt: Timestamp.fromMillis(nowMs),
  });
  await db.doc(`users/${ownerUid}`).set({ displayName: 'Broadcast owner', status: 'active' });
  const base = { db, Timestamp, clock };
  const root = await createServerCreationService(base).createServerV1(request(ownerUid, {
    requestId: randomUUID(), serverType: 'community', templateVersion: 1,
    name: 'Community fixture', description: '', privacy: 'public', defaultLanguage: 'English',
  }));
  const server = db.doc(`clubs/${root.serverId}`);
  const stageQuery = await server.collection('channels').where('kind', '==', 'stage').get();
  const stage = stageQuery.docs[0];
  const room = db.doc(`rooms/${stage.data().roomId}`);
  await server.update({ status: 'active', serverActivationState: 'active' });
  await room.update({ status: 'active', serverActivationState: 'active', hostId: ownerUid });
  let uid = ownerUid;
  if (moderatorHost) {
    uid = `broadcast-moderator-${randomUUID()}`;
    await db.doc(`users/${uid}`).set({ displayName: 'Broadcast moderator', status: 'active' });
    await server.collection('members').doc(uid).set({
      userId: uid, role: 'moderator', authorizationRevision: 1,
    });
  }
  const calls = { ensured: [], deleted: [], deletedBindings: [], revoked: [], ended: [] };
  let ensureHook = null; let deleteBoundHook = null;
  const livekit = {
    assertSupported: () => 'wss://test-fixture.livekit.cloud',
    async mintToken(value) {
      const token = `token-${randomUUID()}`;
      return { serverUrl: 'wss://test-fixture.livekit.cloud', participantToken: token, token,
        roomName: value.binding.livekitRoomName, participantIdentity: value.uid,
        participantName: value.participantName, expiresAtMillis: clock() + 300_000,
        permissions: { canPublish: value.grant.canPublish, canSubscribe: true, canPublishData: true },
        permittedTrackSources: value.grant.permittedTrackSources,
        serverId: value.binding.serverId, channelId: value.binding.channelId,
        roomId: value.binding.roomId, sessionId: value.binding.sessionId, sessionRole: value.sessionRole };
    },
    async revokeParticipant(roomName, userId) {
      calls.revoked.push({ roomName, userId });
      return { revocationRequested: true, revokedBeforeMillis: clock() + 1000 };
    },
    async endRoom(roomName, context) { calls.ended.push({ roomName, context }); return {}; },
    async ensureBroadcastIngress(binding) {
      calls.ensured.push(binding);
      const override = ensureHook ? await ensureHook(binding) : null;
      if (override) return override;
      return { created: true, ingressId: 'ingress_12345678',
        url: 'rtmps://ingress.example.test/live', streamKey: 'never-store-this-key',
        roomName: binding.livekitRoomName, participantIdentity: binding.participantIdentity };
    },
    async deleteBroadcastIngress(id) { calls.deleted.push(id); return {}; },
    async deleteBoundBroadcastIngresses(binding) {
      calls.deletedBindings.push(binding);
      if (deleteBoundHook) return deleteBoundHook(binding);
      return {};
    },
  };
  const sessions = createServerSessionService({ ...base, livekit });
  const broadcast = createServerCommunityBroadcastService({ ...base, livekit });
  const control = createServerSessionControlService({ ...base, livekit });
  const target = { serverId: root.serverId, channelId: stage.id };
  const started = await sessions.startServerChannelSessionV1(request(uid, { ...target, requestId: randomUUID() }));
  const data = (requestId = randomUUID()) => ({ ...target, sessionId: started.sessionId, requestId });
  const sessionReference = stage.ref.collection('channelSessions').doc(started.sessionId);
  return { uid, ownerUid, server, stage, room, livekit, sessions, broadcast, control, calls, target, started, data,
    clock, sessionReference,
    reconcileHost: () => control.reconcileServerSessionParticipant({
      ...target, roomId: started.roomId, sessionId: started.sessionId, userId: uid,
    }),
    admitHost: () => sessions.createServerChannelTokenV1(request(uid, data())),
    setEnsureHook: (hook) => { ensureHook = hook; },
    setDeleteBoundHook: (hook) => { deleteBoundHook = hook; },
    advance: (ms) => { nowMs += ms; } };
}

emulatorTest('OBS credentials require the exact active host token and server-owned mirror', async () => {
  const f = await fixture();
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'permission-denied');
  assert.equal(f.calls.ensured.length, 0);
  await f.admitHost();
  await broadcastUsageReference(db, f.uid).delete();
  await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.started.roomId}`).delete();
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'permission-denied');
  assert.equal(f.calls.ensured.length, 0);
});

emulatorTest('unsafe provider ingress ids never enter Firestore or consume a settled capacity slot', async () => {
  const f = await fixture();
  await f.admitHost();
  const invalidIds = ['../unsafe', 'x'.repeat(129)];
  let attempt = 0;
  f.setEnsureHook((binding) => ({
    created: true,
    ingressId: invalidIds[attempt++],
    url: 'rtmps://ingress.example.test/live',
    streamKey: 'provider-secret-key',
    roomName: binding.livekitRoomName,
    participantIdentity: binding.participantIdentity,
  }));
  for (let index = 0; index < invalidIds.length; index += 1) {
    await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'unavailable');
    const session = (await f.stage.ref.collection('channelSessions').doc(f.started.sessionId).get()).data();
    assert.equal(session.obsIngress, null);
    assert.equal(session.obsIngressProvisioning, null);
    assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
    assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
  }
  assert.equal(f.calls.deletedBindings.length, 2);
});

emulatorTest('one per-account slot fails before provider I/O', async () => {
  const f = await fixture();
  await f.admitHost();
  const foreign = communityBroadcastBinding({ serverId: 'foreign', channelId: 'stage', sessionId: 'session' },
    { roomId: 'room', hostId: f.uid });
  await broadcastUsageReference(db, f.uid).set({
    schemaVersion: 1, ...broadcastSlotBinding(foreign, f.uid), state: 'active',
    operationId: 'a'.repeat(64), leaseId: null, leaseExpiresAtMillis: 0,
    ingressId: 'foreign_ingress', updatedAt: Timestamp.now(),
  });
  await broadcastCapacityReference(db).set({
    schemaVersion: 1, enabled: true, activeCount: 1,
    limit: COMMUNITY_BROADCAST_GLOBAL_CAP, updatedAt: Timestamp.now(),
  });
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'resource-exhausted');
  assert.equal(f.calls.ensured.length, 0);
});

emulatorTest('the global OBS kill switch fails before provider I/O', async () => {
  const f = await fixture();
  await f.admitHost();
  await broadcastCapacityReference(db).set({
    schemaVersion: 1, enabled: false, activeCount: 0,
    limit: COMMUNITY_BROADCAST_GLOBAL_CAP, updatedAt: Timestamp.now(),
  });
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'failed-precondition');
  assert.equal(f.calls.ensured.length, 0);
});

emulatorTest('the global OBS kill switch fences an in-flight provider create before secret disclosure', async () => {
  const f = await fixture();
  await f.admitHost();
  let entered; let release;
  const enteredPromise = new Promise((resolve) => { entered = resolve; });
  const releasePromise = new Promise((resolve) => { release = resolve; });
  f.setEnsureHook(async (binding) => {
    entered();
    await releasePromise;
    return { created: true, ingressId: 'disabled_during_create',
      url: 'rtmps://ingress.example.test/live', streamKey: 'must-not-be-returned',
      roomName: binding.livekitRoomName, participantIdentity: binding.participantIdentity };
  });

  const pending = f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  await enteredPromise;
  await broadcastCapacityReference(db).update({ enabled: false });
  release();
  await reject(pending, 'permission-denied');
  assert.equal(f.calls.deletedBindings.length, 1);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  const capacity = (await broadcastCapacityReference(db).get()).data();
  assert.equal(capacity.enabled, false);
  assert.equal(capacity.activeCount, 0);
});

emulatorTest('the global OBS capacity cap fails before provider I/O', async () => {
  const f = await fixture();
  await f.admitHost();
  await broadcastCapacityReference(db).set({
    schemaVersion: 1, enabled: true, activeCount: 1,
    limit: 1, updatedAt: Timestamp.now(),
  });
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'resource-exhausted');
  assert.equal(f.calls.ensured.length, 0);
});

emulatorTest('a sanction during provider create cannot disclose a key and releases capacity only after delete ACK', async () => {
  const f = await fixture();
  await f.admitHost();
  let entered; let release;
  const enteredPromise = new Promise((resolve) => { entered = resolve; });
  const releasePromise = new Promise((resolve) => { release = resolve; });
  f.setEnsureHook(async (binding) => {
    entered();
    await releasePromise;
    return { created: true, ingressId: 'sanctioned_ingress',
      url: 'rtmps://ingress.example.test/live', streamKey: 'must-not-be-returned',
      roomName: binding.livekitRoomName, participantIdentity: binding.participantIdentity };
  });
  const pending = f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  await enteredPromise;
  await db.doc(`restrictions/${f.uid}`).set({ type: 'communicationMute', expiresAt: null });
  release();
  await reject(pending, 'permission-denied');
  assert.equal(f.calls.deletedBindings.length, 1);
  const session = (await f.stage.ref.collection('channelSessions').doc(f.started.sessionId).get()).data();
  assert.equal(session.obsIngress, null);
  assert.equal(session.obsIngressProvisioning, null);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
});

emulatorTest('only the active Community stage host receives provider credentials and no secret is persisted', async () => {
  const f = await fixture();
  const token = await f.admitHost();
  assert.deepEqual(token.permittedTrackSources,
    ['microphone', 'camera', 'screen_share', 'screen_share_audio']);
  const receipt = await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  assert.equal(receipt.streamKey, 'never-store-this-key');
  assert.equal(f.calls.ensured.length, 1);
  const session = (await f.stage.ref.collection('channelSessions').doc(f.started.sessionId).get()).data();
  assert.equal(session.sourcePolicyVersion, 2);
  assert.equal(session.obsIngress.ingressId, 'ingress_12345678');
  assert.equal(session.obsIngressProvisioning, null);
  assert.equal(JSON.stringify(session).includes('never-store-this-key'), false);
  assert.equal(JSON.stringify(session).includes('rtmps://'), false);
  const member = `broadcast-member-${randomUUID()}`;
  await db.doc(`users/${member}`).set({ displayName: 'Viewer', status: 'active' });
  await f.server.collection('members').doc(member).set({ userId: member, role: 'member', authorizationRevision: 1 });
  await reject(f.broadcast.createServerBroadcastIngressV1(request(member, f.data())), 'permission-denied');
  assert.equal(f.calls.ensured.length, 1);
});

emulatorTest('same-generation replay reuses one per-account and one global capacity slot', async () => {
  const f = await fixture();
  await f.admitHost();
  const first = await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  const replay = await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  assert.equal(replay.ingressId, first.ingressId);
  assert.equal(f.calls.ensured.length, 2);
  const slot = (await broadcastUsageReference(db, f.uid).get()).data();
  assert.equal(slot.state, 'active');
  assert.equal(slot.sessionId, f.started.sessionId);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 1);
});

emulatorTest('losing Community host authority deletes the Stream Key before convergence settles', async () => {
  const f = await fixture({ moderatorHost: true });
  await f.admitHost();
  await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  await f.server.collection('members').doc(f.uid).update({
    role: 'member', authorizationRevision: 2,
  });

  const outcome = await f.control.reconcileServerSessionParticipant({
    ...f.target, roomId: f.started.roomId, sessionId: f.started.sessionId, userId: f.uid,
  });
  assert.equal(outcome.revoked, true);
  assert.equal(outcome.revocationPending, false);
  assert.equal(f.calls.deletedBindings.length, 1);
  assert.equal(f.calls.deletedBindings[0].obsIngressId, 'ingress_12345678');
  assert.equal(f.calls.deletedBindings[0].reconcileObsIngress, false);
  assert.deepEqual(f.calls.revoked.at(-1), {
    roomName: f.calls.ensured[0].livekitRoomName, userId: f.uid,
  });
  const session = (await f.stage.ref.collection('channelSessions')
    .doc(f.started.sessionId).get()).data();
  assert.equal(session.obsIngress, null);
  assert.equal(session.obsIngressProvisioning, null);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
});

emulatorTest('a failed Stream Key deletion never shields the removed host identity', async () => {
  const f = await fixture({ moderatorHost: true });
  await f.admitHost();
  await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  await f.server.collection('members').doc(f.uid).update({
    role: 'member', authorizationRevision: 2,
  });
  f.setDeleteBoundHook(() => {
    throw Object.assign(new Error('test-only cleanup outage'), { code: 'unavailable' });
  });

  await assert.rejects(f.control.reconcileServerSessionParticipant({
    ...f.target, roomId: f.started.roomId, sessionId: f.started.sessionId, userId: f.uid,
  }), /test-only cleanup outage/);
  assert.deepEqual(f.calls.revoked, [{
    roomName: f.calls.ensured[0].livekitRoomName, userId: f.uid,
  }]);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, true);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 1);

  f.advance(120_001);
  f.setDeleteBoundHook(null);
  const completed = await f.control.reconcileServerSessionParticipant({
    ...f.target, roomId: f.started.roomId, sessionId: f.started.sessionId, userId: f.uid,
  });
  assert.equal(completed.revocationPending, false);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
  assert.equal(f.calls.revoked.length, 1, 'the acknowledged human revocation is not repeated');
});

emulatorTest('removing a viewer revokes only that viewer and leaves the host Stream Key intact', async () => {
  const f = await fixture();
  await f.admitHost();
  await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  const member = `broadcast-viewer-${randomUUID()}`;
  await db.doc(`users/${member}`).set({ displayName: 'Broadcast viewer', status: 'active' });
  await f.server.collection('members').doc(member).set({
    userId: member, role: 'member', authorizationRevision: 1,
  });
  await f.sessions.createServerChannelTokenV1(request(member, f.data()));
  await f.server.collection('members').doc(member).delete();

  const outcome = await f.control.reconcileServerSessionParticipant({
    ...f.target, roomId: f.started.roomId, sessionId: f.started.sessionId, userId: member,
  });
  assert.equal(outcome.revoked, true);
  assert.equal(f.calls.deletedBindings.length, 0);
  assert.deepEqual(f.calls.revoked.at(-1), {
    roomName: f.calls.ensured[0].livekitRoomName, userId: member,
  });
  const session = (await f.stage.ref.collection('channelSessions')
    .doc(f.started.sessionId).get()).data();
  assert.equal(session.obsIngress.ingressId, 'ingress_12345678');
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, true);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 1);
});

emulatorTest('global enforcement revokes the human even when OBS deletion fails and retries the exact input', async () => {
  const f = await fixture();
  await f.admitHost();
  await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  const {
    EVENT_COLLECTION, EVENT_TYPES, executeVoiceEnforcementEvent,
  } = require('../staff/voice_enforcement');
  const eventReference = db.collection(EVENT_COLLECTION).doc();
  await Promise.all([
    db.doc(`restrictions/${f.uid}`).set({
      type: EVENT_TYPES.COMMUNICATION_MUTE,
      expiresAt: null,
      voiceEnforcementEventId: eventReference.id,
    }),
    eventReference.set({
      targetUid: f.uid,
      type: EVENT_TYPES.COMMUNICATION_MUTE,
      status: 'pending',
      attemptCount: 0,
    }),
  ]);
  const deleted = [];
  const revoked = [];
  let providerFails = true;
  const control = {
    async findParticipantRooms() { return []; },
    async revokeParticipant(roomName, uid) { revoked.push({ roomName, uid }); },
    async deleteBoundBroadcastIngresses(binding) {
      deleted.push(binding);
      if (providerFails) throw Object.assign(new Error('test-only ingress outage'), { code: 'unavailable' });
    },
  };

  await assert.rejects(
    executeVoiceEnforcementEvent(await eventReference.get(), control),
    /test-only ingress outage/,
  );
  assert.deepEqual(revoked, [{ roomName: f.calls.ensured[0].livekitRoomName, uid: f.uid }]);
  assert.equal((await eventReference.get()).data().status, 'retrying');
  assert.equal((await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.started.roomId}`).get()).exists,
    true, 'the discovery mirror must survive until DeleteIngress is acknowledged');
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, true);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 1);

  const nowMs = Date.now();
  const sessionReference = f.stage.ref.collection('channelSessions').doc(f.started.sessionId);
  const session = (await sessionReference.get()).data();
  await sessionReference.update({
    obsIngressProvisioning: {
      ...session.obsIngressProvisioning,
      startedAtMillis: nowMs - 2,
      leaseExpiresAtMillis: nowMs - 1,
    },
  });
  await broadcastUsageReference(db, f.uid).update({
    leaseExpiresAtMillis: nowMs - 1,
  });
  providerFails = false;
  const completed = await executeVoiceEnforcementEvent(await eventReference.get(), control);
  assert.equal(completed.roomsRevoked, 1);
  assert.equal((await eventReference.get()).data().status, 'completed');
  assert.equal(deleted.length, 2);
  assert.equal(deleted[0].obsIngressId, 'ingress_12345678');
  assert.equal(deleted[1].obsIngressId, 'ingress_12345678');
  assert.equal(deleted[1].reconcileObsIngress, true);
  assert.equal((await db.doc(`activeVoiceSessions/${f.uid}/rooms/${f.started.roomId}`).get()).exists, false);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
});

emulatorTest('a missing session still drains its exact durable OBS slot and provider input', async () => {
  const f = await fixture();
  await f.admitHost();
  await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  await f.stage.ref.collection('channelSessions').doc(f.started.sessionId).delete();
  const cleanup = createServerBroadcastCleanupService({
    db, Timestamp, livekit: f.livekit, clock: f.clock,
  });
  const outcome = await cleanup.reconcileServerHostBroadcast({
    ...f.target, roomId: f.started.roomId, sessionId: f.started.sessionId, hostId: f.uid,
  });
  assert.equal(outcome.cleanupPending, false);
  assert.equal(outcome.cleaned, true);
  assert.equal(f.calls.deletedBindings.length, 1);
  assert.equal(f.calls.deletedBindings[0].obsIngressId, 'ingress_12345678');
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
});

emulatorTest('an in-flight OBS lease never refuses a host end; the terminal worker defers only the provider delete', async () => {
  const f = await fixture();
  await f.admitHost();
  // A thrown CreateIngress has an unknowable remote outcome, so its lease is
  // deliberately kept for the full window. That is the longest real wait.
  f.setEnsureHook(() => { throw new Error('test-only provider timeout'); });
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'unavailable');
  const leaseExpiresAtMillis = (await f.sessionReference.get()).data()
    .obsIngressProvisioning.leaseExpiresAtMillis;
  assert.ok(leaseExpiresAtMillis > f.clock());
  assert.equal((await broadcastUsageReference(db, f.uid).get()).data().state, 'provisioning');

  const ended = await f.sessions.endServerChannelSessionV1(request(f.uid, f.data()));
  assert.equal(ended.status, 'ending');
  assert.equal(ended.cleanupPending, true);
  const jobReference = db.doc(`serverControlOutbox/${ended.operationId}`);
  let job = (await jobReference.get()).data();
  assert.equal(job.hostId, f.uid);
  assert.equal(job.obsIngressId, null);
  assert.equal(job.reconcileObsIngress, true);
  assert.ok(job.terminalDelete, 'recipient revocation is not delayed by the lease');
  assert.equal(job.leaseId, null, 'a deferred pass releases its job lease for the schedule');
  assert.deepEqual(f.calls.revoked.map(({ userId }) => userId), [f.uid]);
  assert.deepEqual(f.calls.ended, []);
  assert.equal((await f.sessionReference.get()).data().status, 'ending');

  f.advance(leaseExpiresAtMillis - f.clock() - 1);
  const early = await f.control.processServerSessionEndPage({ operationId: ended.operationId });
  assert.equal(early.cleanupPending, true);
  assert.deepEqual(f.calls.ended, [], 'no ListIngress/DeleteIngress/DeleteRoom before the lease settles');
  assert.equal(f.calls.revoked.length, 1);
  job = (await jobReference.get()).data();
  assert.equal(job.status, 'pending');
  assert.equal(job.leaseId, null);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, true);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 1);

  f.advance(2);
  const drained = await f.control.processServerSessionEndPage({ operationId: ended.operationId });
  assert.equal(drained.cleanupPending, false);
  assert.equal(f.calls.ended.length, 1);
  assert.equal(f.calls.ended[0].context.reconcileObsIngress, true);
  assert.equal(f.calls.ended[0].context.obsIngressId, null);
  const session = (await f.sessionReference.get()).data();
  assert.equal(session.status, 'ended');
  assert.equal(session.obsIngressProvisioning, null);
  assert.equal((await jobReference.get()).data().status, 'completed');
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
});

emulatorTest('staff suspension and staff deletion stage the end during an in-flight OBS lease', async () => {
  for (const action of ['suspend', 'delete']) {
    const f = await fixture();
    await f.admitHost();
    f.setEnsureHook(() => { throw new Error('test-only provider timeout'); });
    await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'unavailable');
    assert.ok((await f.sessionReference.get()).data().obsIngressProvisioning.leaseExpiresAtMillis > f.clock());
    // The fixture activated only the stage anchor. A staff transaction reads
    // the complete media graph, so activate every anchor exactly as the
    // management suite's fixture does.
    const anchors = await db.collection('rooms').where('serverId', '==', f.target.serverId).get();
    for (const anchor of anchors.docs) {
      await anchor.ref.update({ status: 'active', serverActivationState: 'active', hostId: f.ownerUid });
    }
    const staff = `broadcast-staff-${randomUUID()}`;
    const management = createServerManagementService({ db, Timestamp, clock: f.clock });
    const outcome = action === 'suspend'
      ? await management.staffSetServerModerationStatus({
        serverId: f.target.serverId, suspended: true, reason: 'Abuse report', actorUid: staff,
      })
      : await management.staffDeleteServer({ serverId: f.target.serverId, actorUid: staff });
    assert.equal(outcome.changed, true, action);
    const session = (await f.sessionReference.get()).data();
    assert.equal(session.status, 'ending', action);
    const job = (await db.doc(`serverControlOutbox/${session.endOperationId}`).get()).data();
    assert.equal(job.kind, 'sessionEnd', action);
    assert.equal(job.hostId, f.uid, action);
    assert.equal(job.reconcileObsIngress, true, action);
    assert.deepEqual(f.calls.ended, [], action);
  }
});

emulatorTest('an expired stale invocation cannot delete the ingress reused and committed by a newer lease', async () => {
  const f = await fixture();
  await f.admitHost();
  let releaseFirst; let firstEntered;
  const releaseFirstPromise = new Promise((resolve) => { releaseFirst = resolve; });
  const firstEnteredPromise = new Promise((resolve) => { firstEntered = resolve; });
  let attempts = 0;
  f.setEnsureHook(async (binding) => {
    attempts += 1;
    const receipt = { ingressId: 'ingress_shared',
      url: 'rtmps://ingress.example.test/live', streamKey: 'shared-secret-key',
      roomName: binding.livekitRoomName, participantIdentity: binding.participantIdentity };
    if (attempts === 1) {
      firstEntered();
      await releaseFirstPromise;
      return { ...receipt, created: true };
    }
    return { ...receipt, created: false };
  });
  const stale = f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data('request-stale-0001')));
  const staleRejection = reject(stale, 'permission-denied');
  await firstEnteredPromise;
  f.advance(180_001);
  const current = await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data('request-current-0001')));
  assert.equal(current.ingressId, 'ingress_shared');
  releaseFirst();
  await staleRejection;
  assert.deepEqual(f.calls.deleted, []);
  const session = (await f.stage.ref.collection('channelSessions').doc(f.started.sessionId).get()).data();
  assert.equal(session.obsIngress.ingressId, 'ingress_shared');
  assert.equal(session.obsIngressProvisioning, null);
});

emulatorTest('an uncertain provider failure retains capacity until delayed-create reconciliation', async () => {
  const f = await fixture();
  await f.admitHost();
  f.setEnsureHook(() => { throw new Error('test-only provider failure'); });
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'unavailable');
  let session = (await f.stage.ref.collection('channelSessions').doc(f.started.sessionId).get()).data();
  assert.ok(session.obsIngressProvisioning.leaseExpiresAtMillis > f.clock());
  const reserved = (await broadcastUsageReference(db, f.uid).get()).data();
  assert.equal(reserved.state, 'provisioning');
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 1);
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'aborted');
  f.advance(180_001);
  f.setEnsureHook(null);
  const receipt = await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  assert.equal(receipt.ingressId, 'ingress_12345678');
  session = (await f.stage.ref.collection('channelSessions').doc(f.started.sessionId).get()).data();
  assert.equal(session.obsIngressProvisioning, null);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).data().state, 'active');
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 1);
});

emulatorTest('F1: a connected host can still provision OBS after the 300 s join token expired', async () => {
  const f = await fixture();
  await f.admitHost();
  f.advance(SESSION_TOKEN_TTL_SECONDS * 1000 + 1);
  const receipt = await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  assert.equal(receipt.streamKey, 'never-store-this-key');
  assert.equal(f.calls.ensured.length, 1);
  assert.equal((await f.sessionReference.get()).data().obsIngress.ingressId, 'ingress_12345678');
});

emulatorTest('F1: a host reconcile with unchanged authority after token expiry keeps the live ingress', async () => {
  const f = await fixture();
  await f.admitHost();
  await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  f.advance(SESSION_TOKEN_TTL_SECONDS * 1000 + 1);
  const outcome = await f.reconcileHost();
  assert.equal(outcome.revoked, false);
  assert.equal(outcome.revocationPending, false);
  assert.deepEqual(f.calls.deletedBindings, [], 'no provider ingress deletion');
  assert.deepEqual(f.calls.revoked, []);
  assert.equal((await f.sessionReference.get()).data().obsIngress.ingressId, 'ingress_12345678');
  assert.equal((await broadcastUsageReference(db, f.uid).get()).data().state, 'active');
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 1);
});

emulatorTest('F1: losing host authority after token expiry still deletes the ingress and revokes the human', async () => {
  const f = await fixture({ moderatorHost: true });
  await f.admitHost();
  await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  f.advance(SESSION_TOKEN_TTL_SECONDS * 1000 + 1);
  await f.server.collection('members').doc(f.uid).update({ role: 'member', authorizationRevision: 2 });
  const outcome = await f.reconcileHost();
  assert.equal(outcome.revoked, true);
  assert.equal(f.calls.deletedBindings.length, 1);
  assert.equal((await f.sessionReference.get()).data().obsIngress, null);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
});

emulatorTest('F1: a demoted or removed host cannot provision after token expiry', async () => {
  for (const change of ['demote', 'remove']) {
    const f = await fixture({ moderatorHost: true });
    await f.admitHost();
    f.advance(SESSION_TOKEN_TTL_SECONDS * 1000 + 1);
    const memberReference = f.server.collection('members').doc(f.uid);
    if (change === 'demote') await memberReference.update({ role: 'member', authorizationRevision: 2 });
    else await memberReference.delete();
    await assert.rejects(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())),
      (error) => ['permission-denied', 'not-found'].includes(error.code), change);
    assert.equal(f.calls.ensured.length, 0, change);
    assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false, change);
  }
});

emulatorTest('a missing OBS capacity document means disabled and fails before provider I/O', async () => {
  const f = await fixture();
  await f.admitHost();
  await broadcastCapacityReference(db).delete();
  await reject(f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data())), 'failed-precondition');
  assert.equal(f.calls.ensured.length, 0);
  const session = (await f.sessionReference.get()).data();
  assert.equal(session.obsIngressProvisioning, undefined);
  assert.equal(session.obsIngress, undefined);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).exists, false, 'the callable never creates the switch');
  const rate = (await rateLimitReference(db, COMMUNITY_BROADCAST_RATE_SCOPE, f.uid).get()).data();
  assert.equal(rate.count, 1, 'the refused attempt still consumed the actor budget');
});

emulatorTest('source policy v2 is written only for the Community broadcast stage generation', async () => {
  const f = await fixture();
  assert.equal((await f.sessionReference.get()).data().sourcePolicyVersion, 2);
  const lounge = (await f.server.collection('channels').where('kind', '==', 'voice').get()).docs[0];
  await db.doc(`rooms/${lounge.data().roomId}`).update({
    status: 'active', serverActivationState: 'active', hostId: f.ownerUid,
  });
  const started = await f.sessions.startServerChannelSessionV1(request(f.uid, {
    serverId: f.target.serverId, channelId: lounge.id, requestId: randomUUID(),
  }));
  const session = (await lounge.ref.collection('channelSessions').doc(started.sessionId).get()).data();
  assert.equal(session.sourcePolicyVersion, 1);
  const token = await f.sessions.createServerChannelTokenV1(request(f.uid, {
    serverId: f.target.serverId, channelId: lounge.id, sessionId: started.sessionId, requestId: randomUUID(),
  }));
  assert.deepEqual(token.permittedTrackSources, ['microphone']);
});

emulatorTest('an account ban deletes the host OBS input through global voice enforcement', async () => {
  const f = await fixture();
  await f.admitHost();
  await f.broadcast.createServerBroadcastIngressV1(request(f.uid, f.data()));
  const {
    EVENT_COLLECTION, EVENT_TYPES, executeVoiceEnforcementEvent,
  } = require('../staff/voice_enforcement');
  const eventReference = db.collection(EVENT_COLLECTION).doc();
  await Promise.all([
    db.doc(`users/${f.uid}`).set({ banned: true, banEnforcementEventId: eventReference.id }, { merge: true }),
    eventReference.set({ targetUid: f.uid, type: EVENT_TYPES.BAN, status: 'pending', attemptCount: 0 }),
  ]);
  const deleted = [];
  const revoked = [];
  const control = {
    async findParticipantRooms() { return []; },
    async revokeParticipant(roomName, uid) { revoked.push({ roomName, uid }); },
    async deleteBoundBroadcastIngresses(binding) { deleted.push(binding); return {}; },
  };

  const outcome = await executeVoiceEnforcementEvent(await eventReference.get(), control);
  assert.equal(outcome.roomsRevoked, 1);
  assert.equal((await eventReference.get()).data().status, 'completed');
  assert.equal(deleted.length, 1);
  assert.equal(deleted[0].obsIngressId, 'ingress_12345678');
  assert.deepEqual(revoked, [{ roomName: f.calls.ensured[0].livekitRoomName, uid: f.uid }]);
  assert.equal((await f.sessionReference.get()).data().obsIngress, null);
  assert.equal((await broadcastUsageReference(db, f.uid).get()).exists, false);
  assert.equal((await broadcastCapacityReference(db).get()).data().activeCount, 0);
});

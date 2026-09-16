const {
  digest, fail, requireExactInput, requireId, requireRequestId, requireUid, timestampMillis,
} = require('../integrity/guards');
const { canonicalLiveKitRoomName } = require('./contract');

const COMMUNITY_BROADCAST_SOURCE = 'yovoice.obs.rtmp';
const COMMUNITY_BROADCAST_RATE_SCOPE = 'server.community.broadcast.ingress.v1';
const COMMUNITY_BROADCAST_RATE_LIMIT = Object.freeze({ maxEvents: 2, windowMs: 60_000 });
const COMMUNITY_BROADCAST_GLOBAL_CAP = 25;
// Keep every terminal worker pass within its existing twenty-provider-RPC
// ceiling while still making progress if more than one timed-out CreateIngress
// eventually materialized for the same immutable generation.
const COMMUNITY_BROADCAST_CLEANUP_DELETE_LIMIT = 2;
const COMMUNITY_BROADCAST_CAPACITY_PATH = 'serverRuntimeCapacity/communityBroadcastV1';
const COMMUNITY_BROADCAST_USAGE_COLLECTION = 'serverBroadcastUsage';

function validProvisioningLease(value) {
  if (value === null || value === undefined) return null;
  const keys = value?.schemaVersion === 2
    ? ['schemaVersion', 'operationId', 'leaseId', 'startedAtMillis', 'leaseExpiresAtMillis']
    : ['schemaVersion', 'operationId', 'startedAtMillis', 'leaseExpiresAtMillis'];
  if (typeof value !== 'object' || Array.isArray(value) || ![1, 2].includes(value.schemaVersion) ||
      Object.keys(value).length !== keys.length || keys.some((key) => !Object.hasOwn(value, key)) ||
      typeof value.operationId !== 'string' || !/^[a-f0-9]{64}$/u.test(value.operationId) ||
      (value.schemaVersion === 2 &&
        (typeof value.leaseId !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/u.test(value.leaseId))) ||
      !Number.isSafeInteger(value.startedAtMillis) || value.startedAtMillis < 0 ||
      !Number.isSafeInteger(value.leaseExpiresAtMillis) ||
      value.leaseExpiresAtMillis <= value.startedAtMillis) {
    fail('data-loss', 'The OBS broadcast provisioning state needs reconciliation.');
  }
  return value;
}

function communityBroadcastInput(data) {
  const keys = ['serverId', 'channelId', 'sessionId', 'requestId'];
  requireExactInput(data, keys, keys);
  return {
    serverId: requireId(data.serverId, 'serverId'),
    channelId: requireId(data.channelId, 'channelId'),
    sessionId: requireId(data.sessionId, 'sessionId'),
    requestId: requireRequestId(data.requestId),
  };
}

function communityBroadcastBinding(input, { roomId, hostId }) {
  const serverId = requireId(input.serverId, 'serverId');
  const channelId = requireId(input.channelId, 'channelId');
  const sessionId = requireId(input.sessionId, 'sessionId');
  return Object.freeze({
    schemaVersion: 1,
    source: COMMUNITY_BROADCAST_SOURCE,
    serverId,
    channelId,
    roomId: requireId(roomId, 'roomId'),
    sessionId,
    livekitRoomName: canonicalLiveKitRoomName(serverId, channelId, sessionId),
    hostId: requireUid(hostId, 'hostId'),
    participantIdentity: `obs_${digest(COMMUNITY_BROADCAST_SOURCE, serverId, channelId, sessionId).slice(0, 40)}`,
  });
}

function communityBroadcastMetadata(binding) {
  const keys = ['schemaVersion', 'source', 'serverId', 'channelId', 'roomId', 'sessionId',
    'livekitRoomName', 'hostId', 'participantIdentity'];
  if (!binding || keys.some((key) => !Object.hasOwn(binding, key)) ||
      Object.keys(binding).length !== keys.length || binding.schemaVersion !== 1 ||
      binding.source !== COMMUNITY_BROADCAST_SOURCE ||
      binding.livekitRoomName !== canonicalLiveKitRoomName(
        binding.serverId, binding.channelId, binding.sessionId,
      )) fail('failed-precondition', 'The OBS broadcast binding is invalid.');
  return JSON.stringify(Object.fromEntries(keys.map((key) => [key, binding[key]])));
}

function storedBroadcastIngressId(session, binding) {
  const value = session?.obsIngress;
  if (value === null || value === undefined) return null;
  const keys = ['schemaVersion', 'source', 'ingressId', 'participantIdentity',
    'livekitRoomName', 'configuredById', 'configuredAt'];
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== keys.length || keys.some((key) => !Object.hasOwn(value, key)) ||
      value.schemaVersion !== 1 || value.source !== COMMUNITY_BROADCAST_SOURCE ||
      value.participantIdentity !== binding.participantIdentity ||
      value.livekitRoomName !== binding.livekitRoomName ||
      value.configuredById !== binding.hostId || timestampMillis(value.configuredAt) === null) {
    fail('data-loss', 'The OBS broadcast record needs reconciliation.');
  }
  try { return requireId(value.ingressId, 'ingressId'); }
  catch { fail('data-loss', 'The OBS broadcast record needs reconciliation.'); }
}

function broadcastUsageReference(db, uid) {
  return db.doc(`${COMMUNITY_BROADCAST_USAGE_COLLECTION}/${requireUid(uid)}`);
}

function broadcastCapacityReference(db) {
  return db.doc(COMMUNITY_BROADCAST_CAPACITY_PATH);
}

function broadcastSlotBinding(binding, uid) {
  const canonical = communityBroadcastBinding(binding, {
    roomId: binding.roomId,
    hostId: uid,
  });
  if (binding.livekitRoomName !== canonical.livekitRoomName ||
      (binding.participantIdentity !== undefined &&
        binding.participantIdentity !== canonical.participantIdentity)) {
    fail('failed-precondition', 'The OBS broadcast binding is invalid.');
  }
  return {
    source: COMMUNITY_BROADCAST_SOURCE,
    uid: requireUid(uid),
    serverId: requireId(binding.serverId, 'serverId'),
    channelId: requireId(binding.channelId, 'channelId'),
    roomId: requireId(binding.roomId, 'roomId'),
    sessionId: requireId(binding.sessionId, 'sessionId'),
    livekitRoomName: canonical.livekitRoomName,
    participantIdentity: canonical.participantIdentity,
  };
}

function validateBroadcastSlot(value, uid) {
  const keys = ['schemaVersion', 'source', 'uid', 'serverId', 'channelId', 'roomId', 'sessionId',
    'livekitRoomName', 'participantIdentity', 'state', 'operationId', 'leaseId',
    'leaseExpiresAtMillis', 'ingressId', 'updatedAt'];
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== keys.length || keys.some((key) => !Object.hasOwn(value, key)) ||
      value.schemaVersion !== 1 || value.source !== COMMUNITY_BROADCAST_SOURCE ||
      value.uid !== requireUid(uid) || !['provisioning', 'active'].includes(value.state) ||
      typeof value.operationId !== 'string' || !/^[a-f0-9]{64}$/u.test(value.operationId) ||
      timestampMillis(value.updatedAt) === null) {
    fail('data-loss', 'The OBS broadcast capacity slot needs reconciliation.');
  }
  const binding = communityBroadcastBinding(value, { roomId: value.roomId, hostId: value.uid });
  if (value.livekitRoomName !== binding.livekitRoomName ||
      value.participantIdentity !== binding.participantIdentity) {
    fail('data-loss', 'The OBS broadcast capacity slot needs reconciliation.');
  }
  if (value.state === 'provisioning') {
    if (typeof value.leaseId !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/u.test(value.leaseId) ||
        !Number.isSafeInteger(value.leaseExpiresAtMillis) || value.leaseExpiresAtMillis <= 0 ||
        value.ingressId !== null) {
      fail('data-loss', 'The OBS broadcast capacity slot needs reconciliation.');
    }
  } else if (value.leaseId !== null || value.leaseExpiresAtMillis !== 0) {
    fail('data-loss', 'The OBS broadcast capacity slot needs reconciliation.');
  } else {
    try { requireId(value.ingressId, 'ingressId'); }
    catch { fail('data-loss', 'The OBS broadcast capacity slot needs reconciliation.'); }
  }
  return value;
}

function slotMatchesBinding(slot, binding, uid) {
  const expected = broadcastSlotBinding(binding, uid);
  return Object.entries(expected).every(([key, value]) => slot?.[key] === value);
}

function validateBroadcastCapacity(value) {
  const keys = ['schemaVersion', 'enabled', 'activeCount', 'limit', 'updatedAt'];
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== keys.length || keys.some((key) => !Object.hasOwn(value, key)) ||
      value.schemaVersion !== 1 || typeof value.enabled !== 'boolean' ||
      !Number.isSafeInteger(value.limit) || value.limit < 1 || value.limit > COMMUNITY_BROADCAST_GLOBAL_CAP ||
      !Number.isSafeInteger(value.activeCount) || value.activeCount < 0 ||
      value.activeCount > value.limit || timestampMillis(value.updatedAt) === null) {
    fail('data-loss', 'The OBS broadcast capacity state needs reconciliation.');
  }
  return value;
}

module.exports = {
  COMMUNITY_BROADCAST_RATE_LIMIT,
  COMMUNITY_BROADCAST_RATE_SCOPE,
  COMMUNITY_BROADCAST_SOURCE,
  COMMUNITY_BROADCAST_GLOBAL_CAP,
  COMMUNITY_BROADCAST_CLEANUP_DELETE_LIMIT,
  broadcastCapacityReference,
  broadcastSlotBinding,
  broadcastUsageReference,
  communityBroadcastBinding,
  communityBroadcastInput,
  communityBroadcastMetadata,
  storedBroadcastIngressId,
  slotMatchesBinding,
  validateBroadcastCapacity,
  validateBroadcastSlot,
  validProvisioningLease,
};

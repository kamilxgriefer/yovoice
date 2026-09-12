const { fail, requireExactInput, requireId, requireUid } = require("../integrity/guards");
const { loadLiveKitSdk } = require("../livekit/sdk");
const { createLiveKitControl, isNotFound } = require("../livekit/control");
const { canonicalLiveKitRoomName } = require("./contract");
const { SESSION_TOKEN_TTL_SECONDS } = require("./session_contract");

function cloudUrl(value) {
  let url;
  try { url = new URL(value); } catch { fail("failed-precondition", "Server media is not configured."); }
  if (url.protocol !== "wss:" || !/^[a-z0-9-]+\.livekit\.cloud$/u.test(url.hostname) ||
      url.port || url.username || url.password || url.pathname !== "/" || url.search || url.hash) {
    fail("failed-precondition", "Server media requires the reviewed LiveKit Cloud revocation adapter.");
  }
  return url.origin;
}

/** No secrets or SDK work at module load. Integration must explicitly supply
 * the existing LiveKit secret accessors; this module registers no callable. */
function createServerLiveKitAdapter({ apiKey, apiSecret, serverUrl, client = null, AccessTokenClass = null, clock = Date.now }) {
  if (![apiKey, apiSecret, serverUrl].every((value) => typeof value === "function")) {
    throw new TypeError("Explicit LiveKit configuration accessors are required.");
  }
  let transport = client;
  function assertSupported() { return cloudUrl(serverUrl()); }
  function credentials() {
    const key = apiKey(); const secret = apiSecret();
    if (typeof key !== "string" || !key || typeof secret !== "string" || !secret) {
      fail("failed-precondition", "Server media is not configured.");
    }
    return { key, secret };
  }
  function getClient() {
    const url = assertSupported();
    if (!transport) {
      const { key, secret } = credentials();
      transport = new (loadLiveKitSdk().RoomServiceClient)(url, key, secret, {
        requestTimeout: 4, failover: false,
      });
    }
    return transport;
  }
  function getControl(now = clock, attempts = 2) {
    return createLiveKitControl({ client: getClient(), now, attempts });
  }
  async function endRoom(roomName, context) {
    const keys = ["version", "endOperationId", "serverId", "channelId", "roomId", "sessionId", "livekitRoomName"];
    requireExactInput(context, keys, keys);
    if (context.version !== 1) fail("failed-precondition", "The terminal media binding is unsupported.");
    for (const key of ["endOperationId", "serverId", "channelId", "roomId", "sessionId"]) requireId(context[key], key);
    const expected = canonicalLiveKitRoomName(context.serverId, context.channelId, context.sessionId);
    if (roomName !== expected || context.livekitRoomName !== expected) {
      fail("failed-precondition", "The terminal media generation does not match.");
    }
    // The internal worker first persists the complete token-revocation ledger
    // and checks its owned canonical ending operation. This context binds the
    // transport target; it is not a client-supplied authorization capability.
    // Exactly one RPC, with no legacy roster scan or automatic retry. A job
    // retry can only delete the same immutable old RTC generation again.
    const client = getClient();
    try {
      await client.deleteRoom(expected);
      return { alreadyAbsent: false, attempts: 1 };
    } catch (error) {
      if (isNotFound(error)) return { alreadyAbsent: true, attempts: 1 };
      throw error;
    }
  }
  async function mintToken({ uid, participantName, binding, sessionRole, grant }) {
    const url = assertSupported();
    const { key, secret } = credentials();
    const sdk = loadLiveKitSdk();
    const sources = { microphone: sdk.TrackSource.MICROPHONE, camera: sdk.TrackSource.CAMERA,
      screen_share: sdk.TrackSource.SCREEN_SHARE, screen_share_audio: sdk.TrackSource.SCREEN_SHARE_AUDIO };
    if (!Array.isArray(grant.permittedTrackSources) ||
        grant.permittedTrackSources.some((source) => !Object.hasOwn(sources, source))) {
      fail("failed-precondition", "The session source policy is unsupported.");
    }
    const permissions = {
      canPublish: grant.canPublish, canSubscribe: grant.canSubscribe,
      canPublishData: grant.canPublishData, hidden: false, recorder: false,
      canPublishSources: grant.permittedTrackSources.map((source) => sources[source]),
      canUpdateOwnMetadata: false,
    };
    const token = new (AccessTokenClass ?? sdk.AccessToken)(key, secret, {
      identity: requireUid(uid), name: participantName, ttl: SESSION_TOKEN_TTL_SECONDS,
      metadata: JSON.stringify({ uid, role: sessionRole, serverId: binding.serverId,
        channelId: binding.channelId, roomId: binding.roomId, sessionId: binding.sessionId }),
    });
    token.addGrant({ roomJoin: true, room: binding.livekitRoomName, ...permissions });
    const participantToken = await token.toJwt();
    // The installed SDK owns JWT timestamps. Return its actual expiry, not a
    // guessed expiry from a request that may have spent time waiting on I/O.
    let claims;
    try { claims = JSON.parse(Buffer.from(participantToken.split(".")[1], "base64url").toString("utf8")); }
    catch { fail("internal", "The media token could not be issued."); }
    if (!Number.isSafeInteger(claims.exp) || !Number.isSafeInteger(claims.nbf)) {
      fail("internal", "The media token could not be issued.");
    }
    return { serverUrl: url, participantToken, token: participantToken,
      roomName: binding.livekitRoomName, participantIdentity: uid, participantName,
      expiresAtMillis: claims.exp * 1000, permissions,
      permittedTrackSources: [...grant.permittedTrackSources],
      serverId: binding.serverId, channelId: binding.channelId,
      roomId: binding.roomId, sessionId: binding.sessionId, sessionRole };
  }
  return Object.freeze({ assertSupported, mintToken,
    revokeParticipant: async (roomName, uid) => {
      const cutoffTime = clock();
      // One external attempt only. A timed-out RemoveParticipant can still
      // execute remotely: an automatic retry's ACK cannot prove the first
      // request will not later disconnect a freshly readmitted identity.
      const result = await getControl(() => cutoffTime, 1).revokeParticipant(roomName, uid);
      // Unlike legacy best-effort cleanup, V1 cannot treat absence as proof
      // that a never-joined bearer token was revoked. Cloud's explicit-cutoff
      // API acknowledges offline revocation with success. Whole-generation
      // cleanup may retry its terminal RTC target; per-identity convergence
      // must retain its unresolved attempt instead of dispatching a retry.
      if (result.alreadyAbsent) fail("unavailable", "Media token revocation is not yet confirmed.");
      return { ...result, revokedBeforeMillis: (Math.floor(cutoffTime / 1000) + 1) * 1000 };
    },
    endRoom,
    /**
     * Read-only occupancy of one V1 generation's provider room, for the
     * stale-generation sweep (session_staleness.js). One ListParticipants
     * RPC, no retry. LiveKit deletes a room itself once it has been empty
     * for its `emptyTimeout`, so NOT_FOUND is a positive "nobody is here",
     * not a failure. Any other error propagates: the sweep treats it as an
     * unknown, and an unknown never ends a generation.
     */
    async roomOccupancy(binding) {
      const keys = ["serverId", "channelId", "roomId", "sessionId", "livekitRoomName"];
      requireExactInput(binding, keys, keys);
      const expected = canonicalLiveKitRoomName(binding.serverId, binding.channelId, binding.sessionId);
      if (binding.livekitRoomName !== expected) fail("failed-precondition", "The media generation does not match.");
      const client = getClient();
      try {
        const participants = await client.listParticipants(expected);
        return { present: true, participantCount: Array.isArray(participants) ? participants.length : 0 };
      } catch (error) {
        if (isNotFound(error)) return { present: false, participantCount: 0 };
        throw error;
      }
    } });
}

module.exports = { cloudUrl, createServerLiveKitAdapter };

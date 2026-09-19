const { fail, requireExactInput, requireId, requireUid } = require("../integrity/guards");
const { loadLiveKitSdk } = require("../livekit/sdk");
const { createLiveKitControl, isNotFound } = require("../livekit/control");
const { canonicalLiveKitRoomName } = require("./contract");
const {
  COMMUNITY_BROADCAST_CLEANUP_DELETE_LIMIT,
  communityBroadcastBinding,
  communityBroadcastMetadata,
} = require("./community_broadcast_contract");
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
function createServerLiveKitAdapter({
  apiKey, apiSecret, serverUrl, client = null, ingressClient = undefined,
  AccessTokenClass = null, clock = Date.now,
}) {
  if (![apiKey, apiSecret, serverUrl].every((value) => typeof value === "function")) {
    throw new TypeError("Explicit LiveKit configuration accessors are required.");
  }
  let transport = client;
  let ingressTransport = ingressClient;
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
  function getIngressClient() {
    if (ingressTransport !== undefined) return ingressTransport;
    // Existing unit tests inject only the RoomService transport. Keep that
    // seam isolated; production constructs both clients from the same secret
    // accessors, while ingress tests inject their own explicit transport.
    if (client !== null) return null;
    const url = assertSupported();
    const { key, secret } = credentials();
    ingressTransport = new (loadLiveKitSdk().IngressClient)(url, key, secret, {
      requestTimeout: 4, failover: false,
    });
    return ingressTransport;
  }

  function validateIngress(info, binding, { requireCredentials = true } = {}) {
    const sdk = loadLiveKitSdk();
    const expectedMetadata = communityBroadcastMetadata(binding);
    let ingressId = null;
    try { ingressId = requireId(info?.ingressId, "ingressId"); }
    catch { fail("data-loss", "The OBS broadcast provider binding is invalid."); }
    if (!info || info.roomName !== binding.livekitRoomName ||
        info.participantIdentity !== binding.participantIdentity ||
        info.participantMetadata !== expectedMetadata ||
        info.inputType !== sdk.IngressInput.RTMP_INPUT) {
      fail("data-loss", "The OBS broadcast provider binding is invalid.");
    }
    if (requireCredentials) {
      let endpoint;
      try { endpoint = new URL(info.url); } catch { endpoint = null; }
      if (!endpoint || !["rtmp:", "rtmps:"].includes(endpoint.protocol) ||
          endpoint.username || endpoint.password || endpoint.hash ||
          typeof info.streamKey !== "string" || info.streamKey.length < 8 || info.streamKey.length > 1024) {
        fail("unavailable", "OBS streaming details are not available from the media provider.");
      }
    }
    return { ...info, ingressId };
  }

  function hasIngressCredentials(info) {
    let endpoint;
    try { endpoint = new URL(info?.url); } catch { endpoint = null; }
    return Boolean(endpoint && ["rtmp:", "rtmps:"].includes(endpoint.protocol) &&
      !endpoint.username && !endpoint.password && !endpoint.hash &&
      typeof info?.streamKey === "string" && info.streamKey.length >= 8 && info.streamKey.length <= 1024);
  }

  async function matchingBroadcastIngresses(binding) {
    const ingress = getIngressClient();
    if (ingress === null || typeof ingress?.listIngress !== "function") {
      fail("failed-precondition", "OBS broadcasting is not configured.");
    }
    const listed = await ingress.listIngress({ roomName: binding.livekitRoomName });
    if (!Array.isArray(listed)) fail("data-loss", "The OBS broadcast provider response is invalid.");
    const expectedMetadata = communityBroadcastMetadata(binding);
    const identityRows = listed.filter((item) => item?.participantIdentity === binding.participantIdentity);
    if (identityRows.some((item) => item.participantMetadata !== expectedMetadata)) {
      fail("data-loss", "The OBS participant identity is already bound elsewhere.");
    }
    return identityRows.filter((item) => item.participantMetadata === expectedMetadata);
  }

  async function ensureBroadcastIngress(rawBinding) {
    const binding = communityBroadcastBinding(rawBinding, rawBinding);
    let matches = await matchingBroadcastIngresses(binding);
    if (matches.length > 1) {
      // A provider timeout can hide a successful CreateIngress from its caller.
      // If that happened more than once, collapse the exact metadata-bound
      // duplicates before considering any new create. Work is deliberately
      // bounded; a later retry continues from the provider's remaining rows.
      const validated = matches
        .map((item) => validateIngress(item, binding, { requireCredentials: false }))
        .sort((first, second) => first.ingressId.localeCompare(second.ingressId));
      const survivor = validated.find(hasIngressCredentials) ?? validated[0];
      const extras = validated.filter((item) => item.ingressId !== survivor.ingressId);
      for (const item of extras.slice(0, COMMUNITY_BROADCAST_CLEANUP_DELETE_LIMIT)) {
        await deleteBroadcastIngress(item.ingressId);
      }
      if (extras.length > COMMUNITY_BROADCAST_CLEANUP_DELETE_LIMIT) {
        fail("unavailable", "Duplicate OBS inputs are still being reconciled. Retry shortly.");
      }
      matches = [survivor];
    }
    if (matches.length === 1) {
      const info = validateIngress(matches[0], binding, { requireCredentials: false });
      if (hasIngressCredentials(info)) {
        return { created: false, ingressId: info.ingressId, url: info.url, streamKey: info.streamKey,
          roomName: info.roomName, participantIdentity: info.participantIdentity };
      }
      // LiveKit documents that ListIngress returns the connection settings.
      // If a provider response is incomplete, replace only this exact
      // metadata-bound input so the host can recover usable OBS credentials.
      await deleteBroadcastIngress(info.ingressId);
    }
    const ingress = getIngressClient();
    const sdk = loadLiveKitSdk();
    const info = validateIngress(await ingress.createIngress(sdk.IngressInput.RTMP_INPUT, {
      name: `YO Voice OBS ${binding.sessionId}`,
      roomName: binding.livekitRoomName,
      participantIdentity: binding.participantIdentity,
      participantName: "OBS Broadcasting",
      participantMetadata: communityBroadcastMetadata(binding),
      enableTranscoding: true,
      audio: { name: "OBS audio", source: sdk.TrackSource.SCREEN_SHARE_AUDIO },
      video: { name: "OBS screen", source: sdk.TrackSource.SCREEN_SHARE },
    }), binding);
    return { created: true, ingressId: info.ingressId, url: info.url, streamKey: info.streamKey,
      roomName: info.roomName, participantIdentity: info.participantIdentity };
  }

  async function deleteBroadcastIngress(ingressId) {
    requireId(ingressId, "ingressId");
    const ingress = getIngressClient();
    if (ingress === null || typeof ingress?.deleteIngress !== "function") return { alreadyAbsent: true };
    try {
      await ingress.deleteIngress(ingressId);
      return { alreadyAbsent: false };
    } catch (error) {
      if (isNotFound(error)) return { alreadyAbsent: true };
      throw error;
    }
  }

  async function deleteBoundBroadcastIngresses(context) {
    const ingress = getIngressClient();
    // Test adapters created before the OBS surface intentionally have no
    // ingress transport. Production never takes this branch.
    if (ingress === null) return { cleanupPending: false, deleted: 0 };
    // V1 sessions created before OBS support have no host id in their durable
    // end job and could never own an ingress. Preserve their cleanup path.
    if (context.hostId === undefined) return { cleanupPending: false, deleted: 0 };
    const binding = communityBroadcastBinding(context, { roomId: context.roomId, hostId: context.hostId });
    const storedId = context.obsIngressId === null || context.obsIngressId === undefined
      ? null : requireId(context.obsIngressId, "ingressId");
    const reconcile = context.reconcileObsIngress === undefined
      ? true : context.reconcileObsIngress;
    if (typeof reconcile !== "boolean") fail("failed-precondition", "The OBS cleanup binding is invalid.");
    let deleted = 0;
    if (storedId !== null) {
      await deleteBroadcastIngress(storedId);
      deleted += 1;
    }
    if (!reconcile) return { cleanupPending: false, deleted };
    const owned = await matchingBroadcastIngresses(binding);
    const ids = [...new Set(owned.map((item) => requireId(item.ingressId, "ingressId")))]
      .filter((id) => id !== storedId)
      .sort();
    const page = ids.slice(0, COMMUNITY_BROADCAST_CLEANUP_DELETE_LIMIT);
    for (const ingressId of page) {
      await deleteBroadcastIngress(ingressId);
      deleted += 1;
    }
    return {
      cleanupPending: ids.length > COMMUNITY_BROADCAST_CLEANUP_DELETE_LIMIT,
      deleted,
    };
  }
  async function endRoom(roomName, context) {
    const hasCleanupFields = context && (Object.hasOwn(context, "obsIngressId") ||
      Object.hasOwn(context, "reconcileObsIngress"));
    if (hasCleanupFields && (!Object.hasOwn(context, "obsIngressId") ||
        !Object.hasOwn(context, "reconcileObsIngress"))) {
      fail("failed-precondition", "The OBS cleanup binding is invalid.");
    }
    const keys = ["version", "endOperationId", "serverId", "channelId", "roomId", "sessionId", "livekitRoomName",
      ...(context?.hostId === undefined ? [] : ["hostId"]),
      ...(hasCleanupFields ? ["obsIngressId", "reconcileObsIngress"] : [])];
    requireExactInput(context, keys, keys);
    if (context.version !== 1) fail("failed-precondition", "The terminal media binding is unsupported.");
    for (const key of ["endOperationId", "serverId", "channelId", "roomId", "sessionId"]) requireId(context[key], key);
    if (context.hostId !== undefined) requireUid(context.hostId, "hostId");
    if (hasCleanupFields) {
      if (context.obsIngressId !== null) requireId(context.obsIngressId, "ingressId");
      if (typeof context.reconcileObsIngress !== "boolean") {
        fail("failed-precondition", "The OBS cleanup binding is invalid.");
      }
    }
    const expected = canonicalLiveKitRoomName(context.serverId, context.channelId, context.sessionId);
    if (roomName !== expected || context.livekitRoomName !== expected) {
      fail("failed-precondition", "The terminal media generation does not match.");
    }
    // The internal worker first persists the complete token-revocation ledger
    // and checks its owned canonical ending operation. This context binds the
    // transport target; it is not a client-supplied authorization capability.
    // Exactly one RPC, with no legacy roster scan or automatic retry. A job
    // retry can only delete the same immutable old RTC generation again.
    // Ingress and room absence have different meanings. A missing ingress is
    // harmless only for that ingress; it must never masquerade as proof that
    // the room itself was deleted.
    const ingressCleanup = await deleteBoundBroadcastIngresses(context);
    if (ingressCleanup.cleanupPending) {
      fail("unavailable", "OBS inputs are still being removed. Retry shortly.");
    }
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
  return Object.freeze({ assertSupported, ensureBroadcastIngress, deleteBroadcastIngress,
    deleteBoundBroadcastIngresses, mintToken,
    revokeParticipant: async (roomName, uid) => {
      const cutoffTime = clock();
      // One external attempt only. A timed-out RemoveParticipant can still
      // execute remotely: an automatic retry's ACK cannot prove the first
      // request will not later disconnect a freshly readmitted identity.
      const result = await getControl(() => cutoffTime, 1).revokeParticipant(roomName, uid);
      // NOT_FOUND is terminal only because createLiveKitControl proves that
      // the same request carried revokeTokenTs. A generic provider absence
      // without that proof remains fail-closed in confirmedCutoff().
      return result;
    },
    endRoom,
    /**
     * Read-only occupancy of one V1 generation's provider room, for the
     * stale-generation sweep, the release callable and the `room_finished`
     * path (session_staleness.js). One ListParticipants RPC, no retry.
     * LiveKit deletes a room itself once it has been empty for its
     * `emptyTimeout`, so NOT_FOUND is a positive "nobody is here", not a
     * failure. Any other error propagates: every caller treats it as an
     * unknown, and an unknown never ends a generation.
     *
     * `participantIdentities` is additive: the release callable excludes the
     * leaving caller, whose clean disconnect the provider may not have
     * processed yet. It is null when the provider answer is not a list, so a
     * caller can never exclude an identity it did not actually see.
     */
    async roomOccupancy(binding) {
      const keys = ["serverId", "channelId", "roomId", "sessionId", "livekitRoomName"];
      requireExactInput(binding, keys, keys);
      const expected = canonicalLiveKitRoomName(binding.serverId, binding.channelId, binding.sessionId);
      if (binding.livekitRoomName !== expected) fail("failed-precondition", "The media generation does not match.");
      const client = getClient();
      try {
        const participants = await client.listParticipants(expected);
        const listed = Array.isArray(participants);
        return {
          present: true,
          participantCount: listed ? participants.length : 0,
          participantIdentities: listed
            ? participants.map((participant) => (typeof participant?.identity === "string" ? participant.identity : null))
            : null,
        };
      } catch (error) {
        if (isNotFound(error)) return { present: false, participantCount: 0, participantIdentities: [] };
        throw error;
      }
    } });
}

module.exports = { cloudUrl, createServerLiveKitAdapter };

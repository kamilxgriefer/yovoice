const { randomUUID } = require('node:crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const {
  activeProfile, assertNotRestricted, consumeRateLimit, fail, operationIdentity,
  rateLimitReference, requireActor, requireId, timestampMillis, transactionGetAll,
} = require('../integrity/guards');
const { denied } = require('./authority');
const { readSessionTokenAuthority } = require('./session_authority');
const { hasUnresolvedRevocationAttempt, isCommunityBroadcastChannel } = require('./session_contract');
const {
  COMMUNITY_BROADCAST_RATE_LIMIT, COMMUNITY_BROADCAST_RATE_SCOPE,
  broadcastCapacityReference, broadcastSlotBinding,
  broadcastUsageReference, communityBroadcastBinding, communityBroadcastInput,
  slotMatchesBinding, storedBroadcastIngressId, validProvisioningLease,
  validateBroadcastCapacity, validateBroadcastSlot,
} = require('./community_broadcast_contract');

const COMMUNITY_BROADCAST_KIND = 'server.community.broadcast.ingress.v1';
const PROVISIONING_LEASE_MS = 180_000;

function assertCommunityBroadcastAuthority(access, uid) {
  if (!isCommunityBroadcastChannel(access.server, access.channel) ||
      access.session.sourcePolicyVersion !== 2 || access.session.startedById !== uid ||
      access.session.status !== 'live' || access.capabilities?.moderate !== true ||
      access.participant?.role !== 'host' || access.grant?.canPublish !== true ||
      !access.grant.permittedTrackSources?.includes('screen_share') ||
      !access.grant.permittedTrackSources?.includes('screen_share_audio')) denied();
  return communityBroadcastBinding({
    serverId: access.reference.id,
    channelId: access.channelReference.id,
    sessionId: access.session.sessionId,
  }, {
    roomId: access.roomReference.id,
    hostId: access.session.startedById,
  });
}

function ownsProvisioningLease(lease, operationId, leaseId) {
  return lease?.schemaVersion === 2 && lease.operationId === operationId && lease.leaseId === leaseId;
}

function verifiedProviderIngressId(value) {
  try { return requireId(value, 'ingressId'); }
  catch { fail('unavailable', 'OBS streaming details could not be verified.'); }
}

/** OBS credentials are an extension of an already-issued host admission,
 * rather than a second way to enter the RTC generation. Authority is exactly
 * the predicate that keeps the human host admitted (session_control.js
 * participant reconcile): the recipient is `active`, has no unresolved
 * revocation attempt, is past its reconnect barrier, its fingerprint equals
 * the freshly derived authority, and the server-owned mirror is consistent
 * with it. `recipient.expiresAtMillis` is only the `exp` of the last JWT this
 * host was issued. LiveKit refreshes a connected participant's token itself
 * and the host may mint a new one at any time, so that expiry is not a
 * revocation signal and must never delete a healthy stream or refuse setup.
 * Both the recipient and the mirror are re-read in the same transaction
 * before and after provider I/O, so a ban, membership change or enforcement
 * cleanup can fence a late CreateIngress response before its secret is
 * disclosed. */
async function readAuthorizedCommunityBroadcastAccess({ db, transaction, uid, input, nowMs }) {
  const authority = await readSessionTokenAuthority({ db, transaction, uid, input, nowMs });
  const binding = assertCommunityBroadcastAuthority(authority, uid);
  const recipient = authority.recipient;
  if (!recipient || recipient.revocationState !== 'active' ||
      hasUnresolvedRevocationAttempt(recipient) || recipient.reconnectAfterMillis > nowMs ||
      recipient.authorityFingerprint !== authority.fingerprint) denied();
  const mirrorReference = db.doc(`activeVoiceSessions/${uid}/rooms/${authority.roomReference.id}`);
  const mirrorSnapshot = await transaction.get(mirrorReference);
  const mirror = mirrorSnapshot.exists ? mirrorSnapshot.data() : null;
  const mirrorExpiry = timestampMillis(mirror?.expiresAt);
  if (!mirror || mirror.serverSchemaVersion !== 1 || mirror.clubId !== input.serverId ||
      mirror.roomKind !== 'serverChannel' || mirror.authorityFingerprint !== authority.fingerprint ||
      mirror.tokenEpoch !== recipient.tokenEpoch || mirrorExpiry === null ||
      mirrorExpiry !== recipient.expiresAtMillis ||
      Object.entries(authority.binding).some(([key, value]) => mirror[key] !== value)) denied();
  return { authority, binding, mirrorReference };
}

function createServerCommunityBroadcastService({ db, Timestamp, livekit, clock = Date.now }) {
  if (!db?.runTransaction || !Timestamp?.fromMillis ||
      typeof livekit?.assertSupported !== 'function' ||
      typeof livekit?.ensureBroadcastIngress !== 'function' ||
      typeof livekit?.deleteBroadcastIngress !== 'function' ||
      typeof livekit?.deleteBoundBroadcastIngresses !== 'function') {
    throw new TypeError('Firestore, Timestamp and an ingress-capable LiveKit adapter are required.');
  }

  async function createServerBroadcastIngressV1(request) {
    const input = communityBroadcastInput(request.data);
    const auth = requireActor(request);
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) throw new TypeError('clock must return epoch milliseconds.');
    const now = Timestamp.fromMillis(nowMs);
    const { requestId, ...operationInput } = input;
    const identity = operationIdentity(COMMUNITY_BROADCAST_KIND, auth.uid, requestId, operationInput);
    // operationId is stable for an idempotent request. leaseId is unique to
    // this invocation so a late retry can never mistake a newer lease for its
    // own generation, even when the caller reused requestId.
    const leaseId = randomUUID();
    const rateReference = rateLimitReference(db, COMMUNITY_BROADCAST_RATE_SCOPE, auth.uid);

    // A denied or repeated target consumes the same actor-only budget before
    // any server/session existence is disclosed.
    await db.runTransaction(async (transaction) => {
      const [profile, restriction, rate] = await transactionGetAll(
        transaction, db.doc(`users/${auth.uid}`), db.doc(`restrictions/${auth.uid}`), rateReference,
      );
      activeProfile(profile, 'Your');
      assertNotRestricted(restriction, 'Your', nowMs);
      consumeRateLimit(transaction, rate, {
        reference: rateReference, scope: COMMUNITY_BROADCAST_RATE_SCOPE, uid: auth.uid,
        nowMs, now, ...COMMUNITY_BROADCAST_RATE_LIMIT,
      });
    });

    const plan = await db.runTransaction(async (transaction) => {
      const { authority: access, binding } = await readAuthorizedCommunityBroadcastAccess({
        db, transaction, uid: auth.uid, input, nowMs: clock(),
      });
      livekit.assertSupported();
      const lease = validProvisioningLease(access.session.obsIngressProvisioning);
      if (lease !== null && lease.leaseExpiresAtMillis > clock()) {
        fail('aborted', 'OBS broadcast setup is already in progress. Retry shortly.');
      }
      const usageReference = broadcastUsageReference(db, auth.uid);
      const capacityReference = broadcastCapacityReference(db);
      const [usageSnapshot, capacitySnapshot] = await transactionGetAll(
        transaction, usageReference, capacityReference,
      );
      const slot = usageSnapshot.exists ? validateBroadcastSlot(usageSnapshot.data(), auth.uid) : null;
      if (slot !== null && !slotMatchesBinding(slot, binding, auth.uid)) {
        fail('resource-exhausted', 'Only one OBS broadcast can be active per account.');
      }
      if (slot?.state === 'provisioning' && slot.leaseExpiresAtMillis > clock()) {
        fail('aborted', 'OBS broadcast setup is already in progress. Retry shortly.');
      }
      const capacity = capacitySnapshot.exists
        ? validateBroadcastCapacity(capacitySnapshot.data())
        : null;
      if (slot !== null && (capacity === null || capacity.activeCount < 1)) {
        fail('data-loss', 'The OBS broadcast capacity state needs reconciliation.');
      }
      // Default off: a billed provider resource stays inert after a deploy
      // until an operator creates and enables the runtime capacity document.
      // This deliberately differs from appConfig/gif, where missing = enabled.
      if (capacity === null || !capacity.enabled) {
        fail('failed-precondition', 'OBS broadcasting is temporarily disabled.');
      }
      if (slot === null && capacity.activeCount >= capacity.limit) {
        fail('resource-exhausted', 'OBS broadcast capacity is currently full. Retry later.');
      }
      const slotData = {
        schemaVersion: 1,
        ...broadcastSlotBinding(binding, auth.uid),
        state: 'provisioning',
        operationId: identity.id,
        leaseId,
        leaseExpiresAtMillis: nowMs + PROVISIONING_LEASE_MS,
        ingressId: null,
        updatedAt: now,
      };
      transaction.set(usageReference, slotData);
      if (slot === null) transaction.update(capacityReference, {
        activeCount: capacity.activeCount + 1,
        updatedAt: now,
      });
      transaction.update(access.sessionReference, {
        obsIngressProvisioning: {
          schemaVersion: 2, operationId: identity.id, leaseId,
          startedAtMillis: nowMs, leaseExpiresAtMillis: nowMs + PROVISIONING_LEASE_MS,
        },
        updatedAt: now,
      });
      return { binding, sessionReference: access.sessionReference, leaseId,
        usageReference, capacityReference };
    });

    let ingress = null;
    try {
      ingress = await livekit.ensureBroadcastIngress(plan.binding);
      const ingressId = verifiedProviderIngressId(ingress?.ingressId);
      if (!ingress ||
          typeof ingress.url !== 'string' || !ingress.url ||
          typeof ingress.streamKey !== 'string' || !ingress.streamKey ||
          ingress.roomName !== plan.binding.livekitRoomName ||
          ingress.participantIdentity !== plan.binding.participantIdentity) {
        fail('unavailable', 'OBS streaming details could not be verified.');
      }
      await db.runTransaction(async (transaction) => {
        const { authority: access, binding } = await readAuthorizedCommunityBroadcastAccess({
          db, transaction, uid: auth.uid, input, nowMs: clock(),
        });
        const lease = validProvisioningLease(access.session.obsIngressProvisioning);
        const [slotSnapshot, capacitySnapshot] = await transactionGetAll(
          transaction, plan.usageReference, plan.capacityReference,
        );
        const slot = slotSnapshot.exists ? validateBroadcastSlot(slotSnapshot.data(), auth.uid) : null;
        const capacity = capacitySnapshot.exists
          ? validateBroadcastCapacity(capacitySnapshot.data())
          : null;
        if (!ownsProvisioningLease(lease, identity.id, plan.leaseId) ||
            slot === null || slot.operationId !== identity.id || slot.leaseId !== plan.leaseId ||
            !slotMatchesBinding(slot, binding, auth.uid) ||
            capacity === null || capacity.activeCount < 1 || !capacity.enabled ||
            lease.leaseExpiresAtMillis <= clock() ||
            JSON.stringify(binding) !== JSON.stringify(plan.binding)) denied();
        const committedAt = Timestamp.fromMillis(clock());
        transaction.update(access.sessionReference, {
          obsIngress: {
            schemaVersion: 1,
            source: plan.binding.source,
            ingressId,
            participantIdentity: plan.binding.participantIdentity,
            livekitRoomName: plan.binding.livekitRoomName,
            configuredById: auth.uid,
            configuredAt: committedAt,
          },
          // Credentials deliberately never enter Firestore. The caller gets
          // the provider's current secret over this authorized response only.
          obsIngressProvisioning: null,
          updatedAt: committedAt,
        });
        transaction.update(plan.usageReference, {
          state: 'active',
          leaseId: null,
          leaseExpiresAtMillis: 0,
          ingressId,
          updatedAt: committedAt,
        });
      });
      return {
        schemaVersion: 1,
        serverId: input.serverId,
        channelId: input.channelId,
        sessionId: input.sessionId,
        ingressId,
        serverUrl: ingress.url,
        streamKey: ingress.streamKey,
      };
    } catch (error) {
      // Claim cleanup transactionally before touching the provider. A stale
      // invocation cannot delete an ingress that a newer lease has reused or
      // durably committed. Renewing our exact lease fences a new provisioner
      // while the provider deletion is in flight.
      let cleanupBinding = null;
      try {
        // A thrown provider create has an unknowable remote outcome. Keep the
        // durable lease/capacity slot until its full timeout expires; only a
        // later retry may list the exact metadata after the late RPC can no
        // longer materialize. An immediate empty list is not a deletion ACK.
        if (ingress !== null) {
          cleanupBinding = await db.runTransaction(async (transaction) => {
            const [snapshot, usageSnapshot] = await transactionGetAll(
              transaction, plan.sessionReference, plan.usageReference,
            );
            if (!snapshot.exists || !usageSnapshot.exists) return null;
            const lease = validProvisioningLease(snapshot.data()?.obsIngressProvisioning);
            const slot = validateBroadcastSlot(usageSnapshot.data(), auth.uid);
            if (!ownsProvisioningLease(lease, identity.id, plan.leaseId) ||
                slot.operationId !== identity.id || slot.leaseId !== plan.leaseId ||
                !slotMatchesBinding(slot, plan.binding, auth.uid)) return null;
            const cleanupNowMs = clock();
            transaction.update(plan.sessionReference, {
              obsIngressProvisioning: {
                schemaVersion: 2, operationId: identity.id, leaseId: plan.leaseId,
                startedAtMillis: cleanupNowMs,
                leaseExpiresAtMillis: cleanupNowMs + PROVISIONING_LEASE_MS,
              },
              updatedAt: Timestamp.fromMillis(cleanupNowMs),
            });
            transaction.update(plan.usageReference, {
              leaseExpiresAtMillis: cleanupNowMs + PROVISIONING_LEASE_MS,
              updatedAt: Timestamp.fromMillis(cleanupNowMs),
            });
            const storedId = storedBroadcastIngressId(snapshot.data(), plan.binding);
            return { ...plan.binding, obsIngressId: storedId, reconcileObsIngress: true };
          });
        }
      } catch { /* Preserve the original structured failure. */ }

      if (cleanupBinding !== null) {
        let deletionAcknowledged = false;
        try {
          const outcome = await livekit.deleteBoundBroadcastIngresses(cleanupBinding);
          deletionAcknowledged = outcome?.cleanupPending !== true;
        } catch { /* Keep the cleanup fence until expiry after an uncertain provider result. */ }
        if (deletionAcknowledged) {
          try {
            await db.runTransaction(async (transaction) => {
              const [snapshot, usageSnapshot, capacitySnapshot] = await transactionGetAll(
                transaction, plan.sessionReference, plan.usageReference, plan.capacityReference,
              );
              if (!snapshot.exists || !usageSnapshot.exists || !capacitySnapshot.exists) return;
              const lease = validProvisioningLease(snapshot.data()?.obsIngressProvisioning);
              const slot = validateBroadcastSlot(usageSnapshot.data(), auth.uid);
              const capacity = validateBroadcastCapacity(capacitySnapshot.data());
              if (capacity.activeCount < 1) {
                fail('data-loss', 'The OBS broadcast capacity state needs reconciliation.');
              }
              if (ownsProvisioningLease(lease, identity.id, plan.leaseId) &&
                  slot.operationId === identity.id && slot.leaseId === plan.leaseId &&
                  slotMatchesBinding(slot, plan.binding, auth.uid)) {
                transaction.update(plan.sessionReference, {
                  obsIngress: null,
                  obsIngressProvisioning: null,
                  updatedAt: Timestamp.fromMillis(clock()),
                });
                transaction.delete(plan.usageReference);
                transaction.update(plan.capacityReference, {
                  activeCount: capacity.activeCount - 1,
                  updatedAt: Timestamp.fromMillis(clock()),
                });
              }
            });
          } catch { /* Terminal cleanup can reconcile the metadata-bound input. */ }
        }
      }
      if (error instanceof HttpsError) throw error;
      fail('unavailable', 'OBS broadcast setup is temporarily unavailable. Retry this request.');
    }
  }

  return Object.freeze({ createServerBroadcastIngressV1 });
}

module.exports = {
  COMMUNITY_BROADCAST_KIND,
  PROVISIONING_LEASE_MS,
  assertCommunityBroadcastAuthority,
  createServerCommunityBroadcastService,
  ownsProvisioningLease,
  readAuthorizedCommunityBroadcastAccess,
  validProvisioningLease,
};

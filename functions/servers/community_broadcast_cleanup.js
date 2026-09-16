const { randomUUID } = require('node:crypto');

const { digest, fail } = require('../integrity/guards');
const { assertSessionBinding } = require('./session_contract');
const {
  readAuthorizedCommunityBroadcastAccess,
} = require('./community_broadcast');
const {
  broadcastCapacityReference, broadcastSlotBinding, broadcastUsageReference,
  communityBroadcastBinding, slotMatchesBinding, storedBroadcastIngressId,
  validProvisioningLease, validateBroadcastCapacity, validateBroadcastSlot,
} = require('./community_broadcast_contract');

const CLEANUP_LEASE_MS = 120_000;
const EXPECTED_AUTHORITY_DENIALS = new Set([
  'permission-denied',
  'not-found',
  'failed-precondition',
]);

function ownsCleanupLease(value, operationId, leaseId) {
  return value?.schemaVersion === 2 && value.operationId === operationId &&
    value.leaseId === leaseId;
}

/**
 * Deletes the metadata-bound OBS input when its host no longer has current
 * broadcast authority. A Firestore lease fences CreateIngress while provider
 * deletion is in flight. Provider errors deliberately leave that lease in
 * place: the caller/outbox retries after expiry and can safely repeat the
 * exact ListIngress + DeleteIngress operation.
 */
function createServerBroadcastCleanupService({ db, Timestamp, livekit, clock = Date.now }) {
  if (!db?.runTransaction || !Timestamp?.fromMillis || typeof clock !== 'function') {
    throw new TypeError('Firestore, Timestamp and a clock are required.');
  }

  async function reconcileServerHostBroadcast({ serverId, channelId, roomId, sessionId, hostId }) {
    // Canonicalize every path segment before constructing an Admin SDK path.
    // These inputs come from server-owned jobs, but a malformed durable job
    // must fail closed instead of redirecting cleanup to another document.
    const providerBinding = communityBroadcastBinding({ serverId, channelId, sessionId }, {
      roomId, hostId,
    });
    const sessionReference = db.doc(
      `clubs/${providerBinding.serverId}/channels/${providerBinding.channelId}` +
      `/channelSessions/${providerBinding.sessionId}`,
    );
    const leaseId = randomUUID();
    const operationId = digest('server.community.broadcast.cleanup.v1', {
      serverId: providerBinding.serverId,
      channelId: providerBinding.channelId,
      roomId: providerBinding.roomId,
      sessionId: providerBinding.sessionId,
      hostId: providerBinding.hostId,
      leaseId,
    });
    const usageReference = broadcastUsageReference(db, providerBinding.hostId);
    const capacityReference = broadcastCapacityReference(db);

    const plan = await db.runTransaction(async (transaction) => {
      const [snapshot, usageSnapshot] = await Promise.all([
        transaction.get(sessionReference),
        transaction.get(usageReference),
      ]);
      const session = snapshot.exists ? snapshot.data() : null;
      if (session !== null) {
        assertSessionBinding(session, providerBinding);
        if (session.startedById !== providerBinding.hostId) {
          return { completed: true, cleaned: false };
        }
      }
      const slot = usageSnapshot.exists
        ? validateBroadcastSlot(usageSnapshot.data(), providerBinding.hostId)
        : null;
      const matchingSlot = slot !== null &&
        slotMatchesBinding(slot, providerBinding, providerBinding.hostId)
        ? slot : null;
      const hasSessionEvidence = session !== null &&
        (session.obsIngress != null || session.obsIngressProvisioning != null);
      if (!hasSessionEvidence && matchingSlot === null) {
        return { completed: true, cleaned: false };
      }

      let stillAuthorized = false;
      if (session !== null) {
        try {
          await readAuthorizedCommunityBroadcastAccess({
            db,
            transaction,
            uid: providerBinding.hostId,
            input: {
              serverId: providerBinding.serverId,
              channelId: providerBinding.channelId,
              sessionId: providerBinding.sessionId,
            },
            nowMs: clock(),
          });
          stillAuthorized = true;
        } catch (error) {
          if (!EXPECTED_AUTHORITY_DENIALS.has(error?.code)) throw error;
        }
      }
      if (stillAuthorized) return { completed: true, cleaned: false };

      if (typeof livekit?.assertSupported !== 'function' ||
          typeof livekit?.deleteBoundBroadcastIngresses !== 'function') {
        fail('failed-precondition', 'OBS broadcast cleanup is not configured.');
      }
      livekit.assertSupported();
      const lease = validProvisioningLease(session?.obsIngressProvisioning);
      if ((lease !== null && lease.leaseExpiresAtMillis > clock()) ||
          (matchingSlot?.state === 'provisioning' &&
            matchingSlot.leaseExpiresAtMillis > clock())) {
        return { busy: true };
      }
      const sessionIngressId = session === null
        ? null : storedBroadcastIngressId(session, providerBinding);
      const slotIngressId = matchingSlot?.state === 'active'
        ? matchingSlot.ingressId : null;
      if (sessionIngressId !== null && slotIngressId !== null &&
          sessionIngressId !== slotIngressId) {
        fail('data-loss', 'The OBS broadcast capacity slot needs reconciliation.');
      }
      const obsIngressId = sessionIngressId ?? slotIngressId;
      const nowMs = clock();
      if (session !== null) {
        transaction.update(sessionReference, {
          obsIngressProvisioning: {
            schemaVersion: 2,
            operationId,
            leaseId,
            startedAtMillis: nowMs,
            leaseExpiresAtMillis: nowMs + CLEANUP_LEASE_MS,
          },
          updatedAt: Timestamp.fromMillis(nowMs),
        });
      }
      if (matchingSlot !== null) transaction.set(usageReference, {
        schemaVersion: 1,
        ...broadcastSlotBinding(providerBinding, providerBinding.hostId),
        state: 'provisioning',
        operationId,
        leaseId,
        leaseExpiresAtMillis: nowMs + CLEANUP_LEASE_MS,
        ingressId: null,
        updatedAt: Timestamp.fromMillis(nowMs),
      });
      return {
        binding: {
          ...providerBinding,
          obsIngressId,
          reconcileObsIngress: lease !== null || matchingSlot?.state === 'provisioning' ||
            obsIngressId === null,
        },
        hadSessionLease: session !== null,
        hadCapacitySlot: matchingSlot !== null,
      };
    });

    if (plan.completed) return { cleanupPending: false, cleaned: plan.cleaned };
    if (plan.busy) return { cleanupPending: true, cleaned: false };

    const providerOutcome = await livekit.deleteBoundBroadcastIngresses(plan.binding);
    if (providerOutcome?.cleanupPending === true) {
      // Provider-side deletions made progress, but the exact generation still
      // owns more inputs. Keep both durable leases and the capacity slot until
      // a later retry observes complete absence.
      return { cleanupPending: true, cleaned: false };
    }
    return db.runTransaction(async (transaction) => {
      const reads = [];
      if (plan.hadSessionLease) reads.push(sessionReference);
      if (plan.hadCapacitySlot) reads.push(usageReference, capacityReference);
      const snapshots = [];
      for (const reference of reads) snapshots.push(await transaction.get(reference));
      let index = 0;
      let snapshot = null;
      if (plan.hadSessionLease) {
        snapshot = snapshots[index++];
        if (snapshot.exists) {
          const session = snapshot.data();
          assertSessionBinding(session, providerBinding);
          const lease = validProvisioningLease(session.obsIngressProvisioning);
          if (!ownsCleanupLease(lease, operationId, leaseId)) {
            return { cleanupPending: true, cleaned: false };
          }
        }
      }
      if (plan.hadCapacitySlot) {
        const usageSnapshot = snapshots[index++];
        const capacitySnapshot = snapshots[index];
        if (!usageSnapshot.exists || !capacitySnapshot.exists) {
          return { cleanupPending: true, cleaned: false };
        }
        const slot = validateBroadcastSlot(usageSnapshot.data(), providerBinding.hostId);
        const capacity = validateBroadcastCapacity(capacitySnapshot.data());
        if (slot.operationId !== operationId || slot.leaseId !== leaseId ||
            !slotMatchesBinding(slot, plan.binding, providerBinding.hostId) ||
            capacity.activeCount < 1) {
          return { cleanupPending: true, cleaned: false };
        }
        transaction.delete(usageReference);
        transaction.update(capacityReference, {
          activeCount: capacity.activeCount - 1,
          updatedAt: Timestamp.fromMillis(clock()),
        });
      }
      if (snapshot?.exists) {
        const now = Timestamp.fromMillis(clock());
        transaction.update(sessionReference, {
          obsIngress: null,
          obsIngressProvisioning: null,
          updatedAt: now,
        });
      }
      return { cleanupPending: false, cleaned: true };
    });
  }

  return Object.freeze({ reconcileServerHostBroadcast });
}

module.exports = {
  CLEANUP_LEASE_MS,
  createServerBroadcastCleanupService,
  ownsCleanupLease,
};

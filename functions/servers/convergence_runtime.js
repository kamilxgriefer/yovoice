const { randomUUID } = require("node:crypto");
const { FieldPath } = require("firebase-admin/firestore");
const { digest, fail, requireId, requireSafeInteger, requireUid } = require("../integrity/guards");
const { MAX_SERVER_CHANNELS, canonicalLiveKitRoomName } = require("./contract");
const { assertSessionBinding, tokenRecipientId, validateRecipient } = require("./session_contract");
const { createServerSessionControlService } = require("./session_control");
const { createServerConvergenceService } = require("./convergence");
const { validateEndJob } = require("./convergence_lifecycle");

const LEASE_MS = 120_000;
const RETRY_HINT_MS = 30_000;
const MEMBER_KINDS = new Set(["memberJoined", "memberLeft", "memberRoleChanged"]);
const END_KINDS = new Set(["channelArchive", "channelDelete", "ownershipTransferred"]);
const PROJECTION_KINDS = new Set(["channelAccess", "ownershipTransferred"]);
const grantComplete = (job) => ["completed", "superseded"].includes(job.grantStatus);

function unsupported() { fail("failed-precondition", "The convergence job needs reconciliation."); }

function validateConvergenceJob(job, operationId) {
  if (!job || job.schemaVersion !== 1 || job.convergenceVersion !== 1 || job.operationId !== operationId ||
      (!MEMBER_KINDS.has(job.kind) && !END_KINDS.has(job.kind) && job.kind !== "channelAccess") ||
      !Array.isArray(job.rtcTargets) || job.rtcTargets.length > MAX_SERVER_CHANNELS ||
      !["pending", "completed"].includes(job.status) || !["pending", "completed", "superseded"].includes(job.grantStatus) ||
      !["pending", "completed", "recoveryRequired"].includes(job.rtcStatus) ||
      !Number.isSafeInteger(job.rtcTargetIndex) || job.rtcTargetIndex < 0 || job.rtcTargetIndex > job.rtcTargets.length ||
      !Number.isSafeInteger(job.bridgeLeaseExpiresAtMillis) || job.bridgeLeaseExpiresAtMillis < 0 ||
      !Number.isSafeInteger(job.retryAfterMillis) || job.retryAfterMillis < 0 ||
      typeof job.contentCleanupPending !== "boolean") unsupported();
  requireId(job.serverId, "serverId");
  if (job.bridgeLeaseId !== null) requireId(job.bridgeLeaseId, "bridge lease");
  if (job.rtcRecipientCursor !== null) requireId(job.rtcRecipientCursor, "recipient cursor");
  if (MEMBER_KINDS.has(job.kind)) requireUid(job.userId);
  if (job.kind === "ownershipTransferred") {
    requireUid(job.previousOwnerId); requireUid(job.newOwnerId);
  }
  if (["channelAccess", "channelArchive", "channelDelete"].includes(job.kind)) requireId(job.channelId, "channelId");
  const seen = new Set();
  for (const target of job.rtcTargets) {
    if (!target || typeof target !== "object" || target.serverId !== job.serverId) unsupported();
    for (const key of ["channelId", "roomId", "sessionId"]) requireId(target[key], key);
    if (target.livekitRoomName !== canonicalLiveKitRoomName(job.serverId, target.channelId, target.sessionId)) unsupported();
    if (job.channelId !== undefined && target.channelId !== job.channelId) unsupported();
    const mode = MEMBER_KINDS.has(job.kind) ? "recipient" : END_KINDS.has(job.kind) ? "sessionEnd" : "recipients";
    if (target.mode !== mode) unsupported();
    if (mode === "recipient" && (requireUid(target.userId) !== job.userId || target.endOperationId !== undefined)) unsupported();
    if (mode === "sessionEnd") requireId(target.endOperationId, "endOperationId");
    if (mode !== "recipient" && target.userId !== undefined) unsupported();
    if (mode !== "sessionEnd" && target.endOperationId !== undefined) unsupported();
    const key = `${target.channelId}/${target.sessionId}`;
    if (seen.has(key)) unsupported();
    seen.add(key);
  }
  if ((job.rtcStatus === "completed") !== (job.rtcTargetIndex === job.rtcTargets.length) ||
      (job.rtcStatus === "completed" && job.rtcRecipientCursor !== null) ||
      (job.status === "completed" && (!grantComplete(job) || job.rtcStatus !== "completed" || job.contentCleanupPending)) ||
      (job.contentCleanupPending && job.kind !== "channelDelete") ||
      (!grantComplete(job) && !PROJECTION_KINDS.has(job.kind))) unsupported();
  return job;
}

function immutableJobFingerprint(job) {
  return digest("server.convergence.job.v1", { operationId: job.operationId, kind: job.kind, serverId: job.serverId,
    channelId: job.channelId ?? null, userId: job.userId ?? null,
    membershipRevision: job.membershipRevision ?? null, aclRevision: job.aclRevision ?? null,
    previousOwnerId: job.previousOwnerId ?? null, newOwnerId: job.newOwnerId ?? null,
    rtcTargets: job.rtcTargets, contentCleanupPending: job.contentCleanupPending });
}

function resultFor(job, processed = 0) {
  return { propagationComplete: grantComplete(job), rtcCleanupPending: job.rtcStatus !== "completed",
    cleanupPending: job.status !== "completed", contentCleanupPending: job.contentCleanupPending,
    recoveryRequired: job.rtcStatus === "recoveryRequired", processed };
}

/** Explicit internal worker only. No callable, trigger, scheduler or SDK
 * invocation occurs on import or during held configuration mutations. */
function createServerConvergenceRuntimeService({ db, Timestamp, livekit, clock = Date.now }) {
  const dependencies = { db, Timestamp, livekit, clock };
  const media = createServerSessionControlService(dependencies);
  const projection = createServerConvergenceService(dependencies);

  async function processServerConvergencePage({ operationId, pageSize = 20 }) {
    requireId(operationId, "operationId"); requireSafeInteger(pageSize, "pageSize", { min: 1, max: 20 });
    const reference = db.doc(`serverControlOutbox/${operationId}`); const leaseId = randomUUID();
    const plan = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const job = validateConvergenceJob(snapshot.exists ? snapshot.data() : null, operationId);
      if (job.status === "completed") return { settled: true, job };
      if (job.rtcStatus === "completed" && grantComplete(job)) {
        if (job.contentCleanupPending) return { settled: true, job };
        transaction.update(reference, { status: "completed", completedAt: Timestamp.fromMillis(clock()),
          updatedAt: Timestamp.fromMillis(clock()) });
        return { settled: true, job: { ...job, status: "completed" } };
      }
      if (job.bridgeLeaseId && job.bridgeLeaseExpiresAtMillis > clock()) return { busy: true, job };
      const target = job.rtcTargets[job.rtcTargetIndex] ?? null;
      let recipients = []; let pageDone = true;
      if (target) {
        const sessionReference = db.doc(`clubs/${target.serverId}/channels/${target.channelId}/channelSessions/${target.sessionId}`);
        const session = await transaction.get(sessionReference);
        assertSessionBinding(session.exists ? session.data() : null, target);
        if (target.mode === "sessionEnd") {
          const end = await transaction.get(db.doc(`serverControlOutbox/${target.endOperationId}`));
          validateEndJob(end.exists ? end.data() : null, targetBinding(target), target.endOperationId);
          if (!["ending", "ended"].includes(session.data().status) || session.data().endOperationId !== target.endOperationId) unsupported();
        } else if (target.mode === "recipient") recipients = [{ ...targetBinding(target), userId: target.userId }];
        else {
          let query = sessionReference.collection("tokenRecipients").orderBy(FieldPath.documentId());
          if (job.rtcRecipientCursor !== null) query = query.startAfter(job.rtcRecipientCursor);
          const page = await transaction.get(query.limit(pageSize + 1));
          recipients = page.docs.slice(0, pageSize).map((doc) => {
            const uid = requireUid(doc.data().userId);
            validateRecipient(doc.data(), { ...targetBinding(target), userId: uid, participantIdentity: uid });
            if (doc.id !== tokenRecipientId(uid)) unsupported();
            return { ...targetBinding(target), userId: uid, recipientId: doc.id };
          });
          pageDone = page.size <= pageSize;
        }
      }
      transaction.update(reference, { bridgeLeaseId: leaseId, bridgeLeaseExpiresAtMillis: clock() + LEASE_MS,
        updatedAt: Timestamp.fromMillis(clock()) });
      return { job, target, recipients, pageDone, fingerprint: immutableJobFingerprint(job) };
    });
    if (plan.busy || plan.settled) return resultFor(plan.job);

    let pending = false; let recoveryRequired = false; let errorCode = null; let processed = 0;
    try {
      if (!grantComplete(plan.job)) await projection.processServerControlOutboxPage({ operationId, pageSize });
      if (plan.target?.mode === "sessionEnd") {
        // One terminal target per invocation. Reserve one RPC for final room
        // deletion, in addition to at most 19 recipients. The V1 adapter has
        // no roster fanout or transport retry; its worker checkpoints every
        // cutoff before delete and separately enforces at most 20 actual
        // SDK RPCs per invocation, with at most four concurrent removals.
        const outcome = await media.processServerSessionEndPage({
          operationId: plan.target.endOperationId, pageSize: Math.min(pageSize, 19),
        });
        pending = outcome.cleanupPending; processed = outcome.processed;
      } else {
        for (let offset = 0; offset < plan.recipients.length; offset += 4) {
          const outcomes = await Promise.allSettled(plan.recipients.slice(offset, offset + 4)
            .map((recipient) => media.reconcileServerSessionParticipant(recipient)));
          for (const outcome of outcomes) {
            processed += 1;
            if (outcome.status === "rejected") {
              pending = true; recoveryRequired = true; errorCode = "unavailable";
            } else {
              pending ||= outcome.value.revocationPending;
              recoveryRequired ||= outcome.value.recoveryRequired === true;
            }
          }
        }
      }
    } catch {
      pending = true; errorCode = "unavailable";
    }

    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const current = validateConvergenceJob(snapshot.exists ? snapshot.data() : null, operationId);
      if (current.bridgeLeaseId !== leaseId || immutableJobFingerprint(current) !== plan.fingerprint ||
          current.rtcTargetIndex !== plan.job.rtcTargetIndex || current.rtcRecipientCursor !== plan.job.rtcRecipientCursor) {
        return resultFor(current);
      }
      const patch = { bridgeLeaseId: null, bridgeLeaseExpiresAtMillis: 0,
        retryAfterMillis: pending ? clock() + RETRY_HINT_MS : 0, lastErrorCode: errorCode,
        updatedAt: Timestamp.fromMillis(clock()) };
      if (pending) patch.rtcStatus = recoveryRequired ? "recoveryRequired" : current.rtcStatus;
      else if (plan.target) {
        if (plan.pageDone) {
          patch.rtcTargetIndex = current.rtcTargetIndex + 1; patch.rtcRecipientCursor = null;
          patch.rtcStatus = patch.rtcTargetIndex === current.rtcTargets.length ? "completed" : "pending";
        } else {
          patch.rtcRecipientCursor = plan.recipients.at(-1).recipientId; patch.rtcStatus = "pending";
        }
      }
      const next = { ...current, ...patch };
      if (grantComplete(next) && next.rtcStatus === "completed" && !next.contentCleanupPending) {
        patch.status = "completed"; patch.completedAt = Timestamp.fromMillis(clock());
      }
      transaction.update(reference, patch);
      return resultFor({ ...next, ...patch }, processed);
    });
  }
  return { processServerConvergencePage };
}

function targetBinding(target) {
  return { serverId: target.serverId, channelId: target.channelId, roomId: target.roomId,
    sessionId: target.sessionId, livekitRoomName: target.livekitRoomName };
}

module.exports = { createServerConvergenceRuntimeService, immutableJobFingerprint, validateConvergenceJob };

const { randomUUID } = require("node:crypto");
const { FieldPath } = require("firebase-admin/firestore");
const {
  digest, fail, requireId, requireSafeInteger, requireUid, timestampMillis, transactionGetAll,
} = require("../integrity/guards");
const { canonicalLiveKitRoomName } = require("./contract");
const { assertSessionBinding, hasUnresolvedRevocationAttempt, tokenRecipientId, validateRecipient } = require("./session_contract");
const { readSessionTokenAuthority } = require("./session_authority");

const LEASE_MS = 120_000;
const RECONNECT_SKEW_MS = 2_000;
const EXPECTED_DENIALS = new Set(["permission-denied", "not-found", "failed-precondition"]);

function cleanupBinding(input, userId = null) {
  const serverId = requireId(input.serverId, "serverId");
  const channelId = requireId(input.channelId, "channelId");
  const roomId = requireId(input.roomId, "roomId");
  const sessionId = requireId(input.sessionId, "sessionId");
  return { serverId, channelId, roomId, sessionId,
    livekitRoomName: canonicalLiveKitRoomName(serverId, channelId, sessionId),
    ...(userId === null ? {} : { userId: requireUid(userId), participantIdentity: userId }) };
}

function sessionReference(db, binding) {
  return db.doc(`clubs/${binding.serverId}/channels/${binding.channelId}/channelSessions/${binding.sessionId}`);
}

function mirrorBelongsTo(data, binding, tokenEpoch = null) {
  return data?.serverSchemaVersion === 1 &&
    ["serverId", "channelId", "roomId", "sessionId", "livekitRoomName", "userId", "participantIdentity"]
      .every((key) => data[key] === binding[key]) &&
    (tokenEpoch === null || data.tokenEpoch < tokenEpoch);
}

function confirmedCutoff(result) {
  if (result?.alreadyAbsent === true || !Number.isSafeInteger(result?.revokedBeforeMillis) ||
      result.revokedBeforeMillis <= 0) fail("unavailable", "Offline token revocation is not confirmed.");
  return result.revokedBeforeMillis;
}

function reconnectAfterMillis(nowMs, revokedBeforeMillis) {
  // JWT nbf and Cloud cutoff are whole seconds. Keep the existing two-second
  // post-ACK barrier and at least one additional second beyond the cutoff.
  return Math.max(nowMs + RECONNECT_SKEW_MS, revokedBeforeMillis + 1_000);
}

function invalidEndJob() { fail("failed-precondition", "The media cleanup state needs reconciliation."); }

function endJobBinding(job, operationId) {
  if (!job || job.schemaVersion !== 1 || job.kind !== "sessionEnd" || job.operationId !== operationId ||
      !["pending", "completed"].includes(job.status) ||
      (job.cursor !== null && (typeof job.cursor !== "string" || !/^[a-f0-9]{64}$/u.test(job.cursor))) ||
      !Number.isSafeInteger(job.leaseExpiresAtMillis) || job.leaseExpiresAtMillis < 0 ||
      !Number.isSafeInteger(job.maxTokenExpiresAtMillis) || job.maxTokenExpiresAtMillis < 0) invalidEndJob();
  if (job.leaseId !== null) requireId(job.leaseId, "cleanup lease");
  const binding = cleanupBinding(job);
  if (binding.livekitRoomName !== job.livekitRoomName) invalidEndJob();
  return binding;
}

function sameEndBinding(first, second) {
  return ["serverId", "channelId", "roomId", "sessionId", "livekitRoomName"]
    .every((key) => first[key] === second[key]);
}

function checkpointFingerprint(binding, operationId, authorizationRevision, recipientCursor) {
  return digest("server.session.terminal.delete.v1", binding, operationId, authorizationRevision, recipientCursor);
}

function terminalCheckpoint(job, session, binding) {
  if (!Object.hasOwn(job, "terminalDelete")) return null;
  const checkpoint = job.terminalDelete;
  const keys = ["version", "endOperationId", "bindingFingerprint", "authorizationRevision", "recipientCursor", "readyAt"];
  if (!checkpoint || typeof checkpoint !== "object" || Array.isArray(checkpoint) ||
      Object.keys(checkpoint).length !== keys.length || keys.some((key) => !Object.hasOwn(checkpoint, key)) ||
      checkpoint.version !== 1 || checkpoint.endOperationId !== job.operationId ||
      checkpoint.authorizationRevision !== session.authorizationRevision || checkpoint.recipientCursor !== job.cursor ||
      !Number.isSafeInteger(timestampMillis(checkpoint.readyAt)) || timestampMillis(checkpoint.readyAt) < 0 ||
      checkpoint.bindingFingerprint !== checkpointFingerprint(binding, job.operationId,
        session.authorizationRevision, job.cursor)) invalidEndJob();
  return checkpoint;
}

function checkpointIdentity(checkpoint) {
  return checkpoint === null ? null : digest("server.session.terminal.checkpoint.v1",
    { ...checkpoint, readyAt: timestampMillis(checkpoint.readyAt) });
}

function assertEndGeneration(job, session, binding, operationId, authorizationRevision = null) {
  if (!sameEndBinding(endJobBinding(job, operationId), binding)) invalidEndJob();
  assertSessionBinding(session, binding);
  if (session.endOperationId !== operationId || job.maxTokenExpiresAtMillis !== session.maxTokenExpiresAtMillis ||
      (authorizationRevision !== null && session.authorizationRevision !== authorizationRevision) ||
      session.status !== (job.status === "completed" ? "ended" : "ending")) invalidEndJob();
}

async function readCleanupCursor(transaction, sessionRef, binding, cursor) {
  if (cursor === null) return;
  const snapshot = await transaction.get(sessionRef.collection("tokenRecipients").doc(cursor));
  if (!snapshot.exists) invalidEndJob();
  const recipient = snapshot.data();
  validateRecipient(recipient, cleanupBinding(binding, recipient.userId));
  if (snapshot.id !== tokenRecipientId(recipient.userId) || recipient.revocationState !== "revoked") invalidEndJob();
  confirmedCutoff({ revokedBeforeMillis: recipient.revokedBeforeMillis });
}

async function assertEmptyRecipientTail(transaction, sessionRef, cursor) {
  let query = sessionRef.collection("tokenRecipients").orderBy(FieldPath.documentId());
  if (cursor !== null) query = query.startAfter(cursor);
  if (!(await transaction.get(query.limit(1))).empty) invalidEndJob();
}

/** Internal worker factories only. They require explicit scheduler/trigger
 * wiring in a later reviewed activation. No client may supply these targets. */
function createServerSessionControlService({ db, Timestamp, livekit, clock = Date.now }) {
  async function releaseLease(reference, leaseId, binding, operationId, authorizationRevision) {
    await db.runTransaction(async (transaction) => {
      const current = await transaction.get(reference);
      if (!current.exists || current.data().leaseId !== leaseId) return;
      const session = await transaction.get(sessionReference(db, binding));
      // Even a late failure only releases its own old generation's lease.
      // Never repair or normalize a malformed checkpoint while handling I/O.
      try {
        assertEndGeneration(current.data(), session.data(), binding, operationId, authorizationRevision);
        terminalCheckpoint(current.data(), session.data(), binding);
      } catch { return; }
      if (current.data().status === "pending") transaction.update(reference, {
        leaseId: null, leaseExpiresAtMillis: 0, lastErrorCode: "unavailable", updatedAt: Timestamp.fromMillis(clock()),
      });
    });
  }

  async function processServerSessionEndPage({ operationId, pageSize = 20 }) {
    requireId(operationId, "operationId");
    requireSafeInteger(pageSize, "pageSize", { min: 1, max: 20 });
    const reference = db.doc(`serverControlOutbox/${operationId}`);
    const leaseId = randomUUID();
    const plan = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const job = snapshot.exists ? snapshot.data() : null;
      const binding = endJobBinding(job, operationId);
      const sessionRef = sessionReference(db, binding);
      const session = (await transaction.get(sessionRef)).data();
      assertEndGeneration(job, session, binding, operationId);
      const checkpoint = terminalCheckpoint(job, session, binding);
      if (job.status === "completed" && checkpoint === null) invalidEndJob();
      if (job.leaseId && job.leaseExpiresAtMillis > clock()) return { busy: true };
      await readCleanupCursor(transaction, sessionRef, binding, job.cursor);
      if (checkpoint !== null) await assertEmptyRecipientTail(transaction, sessionRef, job.cursor);
      if (job.status === "completed") return { completed: true };
      const common = { binding, sessionRef, authorizationRevision: session.authorizationRevision,
        originalCursor: job.cursor, checkpoint };
      const now = Timestamp.fromMillis(clock());
      if (checkpoint !== null) {
        transaction.update(reference, { leaseId, leaseExpiresAtMillis: clock() + LEASE_MS, updatedAt: now });
        return { ...common, recipients: [], done: true };
      }
      let query = sessionRef.collection("tokenRecipients").orderBy(FieldPath.documentId());
      if (job.cursor !== null) query = query.startAfter(job.cursor);
      const page = await transaction.get(query.limit(pageSize + 1));
      const recipients = page.docs.slice(0, pageSize).map((doc) => {
        const data = doc.data();
        const expected = cleanupBinding(binding, data.userId);
        validateRecipient(data, expected);
        if (data.tokenEpoch >= Number.MAX_SAFE_INTEGER - 1) fail("data-loss", "The media token epoch is exhausted.");
        if (doc.id !== tokenRecipientId(data.userId)) fail("data-loss", "The private recipient path is invalid.");
        return { reference: doc.ref, data, binding: expected };
      });
      transaction.update(reference, { leaseId, leaseExpiresAtMillis: clock() + LEASE_MS, updatedAt: now });
      for (const item of recipients) {
        if (item.data.revocationState !== "revoked") transaction.update(item.reference, {
          revocationState: "revoking",
          tokenEpoch: item.data.revocationState === "revoking" ? item.data.tokenEpoch : item.data.tokenEpoch + 1,
          updatedAt: now,
        });
      }
      return { ...common, recipients, done: page.size <= pageSize };
    });
    if (plan.completed) return { cleanupPending: false, processed: 0 };
    if (plan.busy) return { cleanupPending: true, processed: 0 };
    let processed = 0;
    try {
      livekit.assertSupported();
      let checkpoint = plan.checkpoint;
      let sdkDispatches = 0;
      if (checkpoint === null) {
        const revocationReceipts = new Map();
        // Issued-but-never-online identities are part of this ledger. Each
        // started RPC is awaited, including a failed batch's remaining calls.
        // The adapter makes one attempt and requires positive Cloud cutoff.
        for (let offset = 0; offset < plan.recipients.length; offset += 4) {
          const outcomes = await Promise.allSettled(plan.recipients.slice(offset, offset + 4).map(async (item) => {
            if (item.data.revocationState !== "revoked") {
              sdkDispatches += 1;
              const result = await livekit.revokeParticipant(plan.binding.livekitRoomName, item.binding.participantIdentity);
              revocationReceipts.set(item.reference.id, confirmedCutoff(result));
            } else {
              revocationReceipts.set(item.reference.id, confirmedCutoff({ revokedBeforeMillis: item.data.revokedBeforeMillis }));
            }
          }));
          const failed = outcomes.find((outcome) => outcome.status === "rejected");
          if (failed) throw failed.reason;
        }
        const receipt = await db.runTransaction(async (transaction) => {
          const [currentSnapshot, sessionSnapshot] = await transactionGetAll(transaction, reference, plan.sessionRef);
          const current = currentSnapshot.data(); const session = sessionSnapshot.data();
          if (current?.leaseId !== leaseId || current.leaseExpiresAtMillis <= clock()) return null;
          assertEndGeneration(current, session, plan.binding, operationId, plan.authorizationRevision);
          if (current.status !== "pending" || current.cursor !== plan.originalCursor ||
              terminalCheckpoint(current, session, plan.binding) !== null) invalidEndJob();
          const related = [];
          for (const item of plan.recipients) related.push(
            item.reference,
            db.doc(`rooms/${plan.binding.roomId}/participants/${item.binding.userId}`),
            db.doc(`activeVoiceSessions/${item.binding.userId}/rooms/${plan.binding.roomId}`));
          const snapshots = related.length ? await transactionGetAll(transaction, ...related) : [];
          const cursor = plan.recipients.at(-1)?.reference.id ?? current.cursor;
          if (plan.done) await assertEmptyRecipientTail(transaction, plan.sessionRef, cursor);
          const now = Timestamp.fromMillis(clock());
          const terminalDelete = plan.done ? { version: 1, endOperationId: operationId,
            authorizationRevision: plan.authorizationRevision, recipientCursor: cursor, readyAt: now,
            bindingFingerprint: checkpointFingerprint(plan.binding, operationId, plan.authorizationRevision, cursor) } : null;
          for (let index = 0; index < plan.recipients.length; index += 1) {
            const item = plan.recipients[index];
            const [recipient, participant, mirror] = snapshots.slice(index * 3, index * 3 + 3);
            const data = validateRecipient(recipient.data(), item.binding);
            const expectedEpoch = item.data.tokenEpoch + (item.data.revocationState === "active" ? 1 : 0);
            if (data.tokenEpoch !== expectedEpoch || data.authorityFingerprint !== item.data.authorityFingerprint ||
                data.revocationState !== (item.data.revocationState === "revoked" ? "revoked" : "revoking")) invalidEndJob();
            transaction.update(item.reference, { revocationState: "revoked", revokedAt: now,
              revokedBeforeMillis: revocationReceipts.get(item.reference.id),
              reconnectAfterMillis: clock() + RECONNECT_SKEW_MS, updatedAt: now });
            if (participant.exists && participant.data()?.serverSchemaVersion === 1 &&
                participant.data()?.sessionId === plan.binding.sessionId &&
                participant.data()?.serverId === plan.binding.serverId &&
                participant.data()?.channelId === plan.binding.channelId &&
                participant.data()?.userId === item.binding.userId &&
                participant.data()?.tokenAuthorityFingerprint === item.data.authorityFingerprint) transaction.delete(participant.ref);
            if (mirror.exists && mirrorBelongsTo(mirror.data(), item.binding) &&
                mirror.data().authorityFingerprint === item.data.authorityFingerprint) transaction.delete(mirror.ref);
          }
          // This checkpoint is a server-owned state-machine receipt, not a
          // cryptographic capability. The full scan's durable page ACKs are
          // the completeness proof; the fingerprint only binds their scope.
          const keepLease = terminalDelete !== null && sdkDispatches < 20;
          transaction.update(reference, { cursor, ...(terminalDelete === null ? {} : { terminalDelete }),
            leaseId: keepLease ? leaseId : null,
            leaseExpiresAtMillis: keepLease ? clock() + LEASE_MS : 0,
            lastErrorCode: null, updatedAt: now });
          return { terminalDelete };
        });
        if (receipt === null) return { cleanupPending: true, processed: 0 };
        processed = plan.recipients.length;
        checkpoint = receipt.terminalDelete;
        // Twenty actual removal RPCs consume this invocation's full budget.
        // Ready survives a crash here; the next pass is strictly delete-only.
        if (checkpoint === null || sdkDispatches >= 20) return { cleanupPending: true, processed };
      }
      const prepared = await db.runTransaction(async (transaction) => {
        const [currentSnapshot, sessionSnapshot] = await transactionGetAll(transaction, reference, plan.sessionRef);
        const current = currentSnapshot.data(); const session = sessionSnapshot.data();
        if (current?.leaseId !== leaseId || current.leaseExpiresAtMillis <= clock()) return false;
        assertEndGeneration(current, session, plan.binding, operationId, plan.authorizationRevision);
        if (current.status !== "pending" ||
            checkpointIdentity(terminalCheckpoint(current, session, plan.binding)) !== checkpointIdentity(checkpoint)) invalidEndJob();
        await readCleanupCursor(transaction, plan.sessionRef, plan.binding, current.cursor);
        await assertEmptyRecipientTail(transaction, plan.sessionRef, current.cursor);
        transaction.update(reference, { leaseExpiresAtMillis: clock() + LEASE_MS, updatedAt: Timestamp.fromMillis(clock()) });
        return true;
      });
      if (!prepared) return { cleanupPending: true, processed };
      await livekit.endRoom(plan.binding.livekitRoomName, { version: 1, endOperationId: operationId, ...plan.binding });
      return await db.runTransaction(async (transaction) => {
        const [currentSnapshot, sessionSnapshot, room] = await transactionGetAll(transaction, reference,
          plan.sessionRef, db.doc(`rooms/${plan.binding.roomId}`));
        const current = currentSnapshot.data(); const session = sessionSnapshot.data();
        if (current?.leaseId !== leaseId || current.leaseExpiresAtMillis <= clock()) return { cleanupPending: true, processed };
        assertEndGeneration(current, session, plan.binding, operationId, plan.authorizationRevision);
        if (current.status !== "pending" ||
            checkpointIdentity(terminalCheckpoint(current, session, plan.binding)) !== checkpointIdentity(checkpoint)) invalidEndJob();
        const now = Timestamp.fromMillis(clock());
        transaction.update(plan.sessionRef, { status: "ended", rtcEndedAt: now, updatedAt: now });
        // Late effects always target the old RTC name; a stale ACK cannot
        // erase a newer or rebound anchor, roster or active-session mirror.
        const anchor = room.exists ? room.data() : null;
        if (anchor?.serverSchemaVersion === 1 && anchor.serverId === plan.binding.serverId &&
            anchor.channelId === plan.binding.channelId && anchor.clubId === plan.binding.serverId &&
            anchor.serverSessionCleanupId === plan.binding.sessionId &&
            anchor.isLive === false && anchor.voiceSessionId === null && anchor.livekitRoomName === null) {
          transaction.update(room.ref, { serverSessionCleanupId: null, participantCount: 0, updatedAt: now });
        }
        transaction.update(reference, { status: "completed",
          leaseId: null, leaseExpiresAtMillis: 0, lastErrorCode: null,
          completedAt: now, updatedAt: now });
        return { cleanupPending: false, processed };
      });
    } catch (error) {
      await releaseLease(reference, leaseId, plan.binding, operationId, plan.authorizationRevision);
      throw error;
    }
  }

  /** Per-identity convergence seam for membership/ACL/sanction outboxes.
   * Re-reads current authority, not a stale event's claimed permissions. */
  async function reconcileServerSessionParticipant({ serverId, channelId, roomId, sessionId, userId }) {
    const binding = cleanupBinding({ serverId, channelId, roomId, sessionId }, userId);
    const sessionRef = sessionReference(db, binding);
    const recipientRef = sessionRef.collection("tokenRecipients").doc(tokenRecipientId(userId));
    const attemptId = randomUUID();
    const plan = await db.runTransaction(async (transaction) => {
      const [session, recipientSnapshot] = await transactionGetAll(transaction, sessionRef, recipientRef);
      assertSessionBinding(session.exists ? session.data() : null, binding);
      if (!recipientSnapshot.exists) return { completed: true };
      const recipient = validateRecipient(recipientSnapshot.data(), binding);
      // Whole-generation cleanup already settled this bound identity. Keep
      // any unresolved attempt as historical evidence, not actionable work.
      // An ending or still-live generation must retain its admission barrier.
      if (session.data().status === "ended" && recipient.revocationState === "revoked") {
        return { completed: true };
      }
      if (recipient.tokenEpoch >= Number.MAX_SAFE_INTEGER - 1) fail("data-loss", "The media token epoch is exhausted.");
      if (hasUnresolvedRevocationAttempt(recipient) || recipient.revocationState === "revoking") {
        // Expiry is observational, not fencing of an external side effect.
        // Never reclaim an unresolved attempt for this live RTC identity.
        // A crash before dispatch, lost response or lost durable ACK therefore
        // stays fail-closed. Authorized whole-generation end is the recovery
        // path: future generations use a different immutable RTC room name.
        return { busy: true, recoveryRequired: !recipient.revocationAttempt ||
          recipient.revocationAttempt.state === "uncertain" ||
          recipient.revocationAttempt.leaseExpiresAtMillis <= clock() };
      }
      if (recipient.revocationState === "revoked") return { completed: true };
      let current = null;
      try {
        current = await readSessionTokenAuthority({ db, transaction, uid: userId,
          input: { serverId, channelId, sessionId }, nowMs: clock() });
      } catch (error) {
        if (!EXPECTED_DENIALS.has(error?.code)) throw error;
      }
      if (recipient.revocationState === "active" && current?.fingerprint === recipient.authorityFingerprint) return { completed: true };
      // This accessor is local validation only, before committing an attempt
      // that would otherwise become uncertain without any provider dispatch.
      livekit.assertSupported();
      const epoch = recipient.tokenEpoch + 1;
      const nowMs = clock();
      transaction.update(recipientRef, { revocationState: "revoking", tokenEpoch: epoch,
        revocationAttempt: { schemaVersion: 1, id: attemptId, tokenEpoch: epoch,
          state: "pending", startedAtMillis: nowMs, leaseExpiresAtMillis: nowMs + LEASE_MS },
        updatedAt: Timestamp.fromMillis(nowMs) });
      return { epoch };
    });
    if (plan.completed) return { revocationPending: false, revoked: false };
    if (plan.busy) return { revocationPending: true, revoked: false, recoveryRequired: plan.recoveryRequired };
    let revokedBeforeMillis;
    try {
      const result = await livekit.revokeParticipant(binding.livekitRoomName, binding.participantIdentity);
      revokedBeforeMillis = confirmedCutoff(result);
    } catch (error) {
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(recipientRef);
        const recipient = validateRecipient(snapshot.data(), binding);
        if (recipient.tokenEpoch === plan.epoch && recipient.revocationAttempt?.id === attemptId &&
            recipient.revocationAttempt.state === "pending") transaction.update(recipientRef, {
          revocationAttempt: { ...recipient.revocationAttempt, state: "uncertain" },
          updatedAt: Timestamp.fromMillis(clock()),
        });
      });
      throw error;
    }
    return db.runTransaction(async (transaction) => {
      const [recipient, participant, mirror] = await transactionGetAll(transaction, recipientRef,
        db.doc(`rooms/${roomId}/participants/${userId}`), db.doc(`activeVoiceSessions/${userId}/rooms/${roomId}`));
      validateRecipient(recipient.data(), binding);
      if (recipient.data().tokenEpoch !== plan.epoch || recipient.data().revocationState !== "revoking" ||
          recipient.data().revocationAttempt?.id !== attemptId ||
          recipient.data().revocationAttempt.state !== "pending") {
        return { revocationPending: recipient.data().revocationState === "revoking", revoked: false };
      }
      const nowMs = clock();
      const now = Timestamp.fromMillis(nowMs);
      transaction.update(recipientRef, { revocationState: "revoked", revokedAt: now,
        revokedBeforeMillis,
        revocationAttempt: { ...recipient.data().revocationAttempt, state: "acknowledged",
          revokedBeforeMillis, acknowledgedAtMillis: nowMs },
        reconnectAfterMillis: reconnectAfterMillis(nowMs, revokedBeforeMillis), updatedAt: now });
      // Preserve the canonical session role/moderator mute for subsequent
      // admissions; deleting it would silently undo a role demotion.
      if (participant.exists && participant.data()?.serverSchemaVersion === 1 &&
          participant.data()?.serverId === serverId && participant.data()?.channelId === channelId &&
          participant.data()?.sessionId === sessionId && participant.data()?.userId === userId) {
        transaction.update(participant.ref, { isMuted: true, updatedAt: now });
      }
      if (mirror.exists && mirrorBelongsTo(mirror.data(), binding, plan.epoch) &&
          mirror.data().authorityFingerprint === recipient.data().authorityFingerprint) transaction.delete(mirror.ref);
      return { revocationPending: false, revoked: true };
    });
  }

  return { processServerSessionEndPage, reconcileServerSessionParticipant };
}

module.exports = { RECONNECT_SKEW_MS, cleanupBinding, createServerSessionControlService, mirrorBelongsTo, reconnectAfterMillis };

const { FieldPath } = require("firebase-admin/firestore");
const { fail, requireId, requireSafeInteger, requireUid, transactionGetAll } = require("../integrity/guards");
const { canonicalChannel, canonicalMember, canonicalServer } = require("./authority");
const { membershipMirror, writeChannelGrant } = require("./documents");
const { serverChannelRefId } = require("./contract");

/**
 * Internal, bounded Firestore projection worker. This is not a callable and
 * deliberately does not mark RTC-dependent jobs complete: the explicit
 * convergence runtime worker owns RTC completion, never this projection.
 */
function createServerConvergenceService({ db, Timestamp, clock = Date.now }) {
  async function processServerControlOutboxPage({ operationId, pageSize = 50 }) {
    requireId(operationId, "operationId");
    requireSafeInteger(pageSize, "pageSize", { min: 1, max: 50 });
    const now = Timestamp.fromMillis(clock());
    return db.runTransaction(async (transaction) => {
      const reference = db.doc(`serverControlOutbox/${operationId}`);
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) fail("not-found", "The convergence operation is unavailable.");
      const job = snapshot.data();
      if (job.schemaVersion !== 1 || job.operationId !== operationId ||
          !["channelAccess", "serverMetadata", "ownershipTransferred"].includes(job.kind)) {
        fail("failed-precondition", "This operation requires its scoped cleanup worker.");
      }
      const serverId = requireId(job.serverId, "serverId");
      const serverReference = db.doc(`clubs/${serverId}`);
      const channelReference = job.kind === "channelAccess"
        ? serverReference.collection("channels").doc(requireId(job.channelId, "channelId")) : null;
      const [root, channelSnapshot] = await transactionGetAll(transaction,
        serverReference, ...[channelReference].filter(Boolean));
      const server = canonicalServer(root, { allowHeld: true });
      if (job.kind === "ownershipTransferred") {
        const uids = [...new Set([requireUid(job.previousOwnerId), requireUid(job.newOwnerId)])];
        if (job.grantStatus === "completed") return { propagationComplete: true, cleanupPending: true, processed: 0 };
        const snapshots = await transactionGetAll(transaction,
          ...uids.map((uid) => serverReference.collection("members").doc(uid)));
        const members = snapshots.map((snapshot, index) => {
          try { return canonicalMember(snapshot, uids[index], server); } catch { return null; }
        });
        let query = serverReference.collection("channels").orderBy(FieldPath.documentId());
        if (job.grantCursor != null) query = query.startAfter(requireId(job.grantCursor, "grant cursor"));
        const page = await transaction.get(query.limit(pageSize + 1));
        const items = page.docs.slice(0, pageSize);
        const channels = items.map((item) => canonicalChannel(item, serverId, { allowArchived: true, allowDeleting: true }));
        for (let index = 0; index < items.length; index += 1) {
          for (let memberIndex = 0; memberIndex < uids.length; memberIndex += 1) {
            const uid = uids[memberIndex]; const member = members[memberIndex];
            if (member && channels[index].status !== "deleting") writeChannelGrant({
              db, transaction, serverId, channelId: items[index].id, channel: channels[index], member, now,
            });
            else {
              transaction.delete(items[index].ref.collection("accessGrants").doc(uid));
              transaction.delete(db.doc(`users/${uid}/serverChannelRefs/${serverChannelRefId(serverId, items[index].id)}`));
            }
          }
        }
        members.forEach((member, index) => {
          const mirror = db.doc(`users/${uids[index]}/clubs/${serverId}`);
          if (member) transaction.set(mirror, membershipMirror(serverId, server, member));
          else transaction.delete(mirror);
        });
        const done = page.size <= pageSize;
        transaction.update(reference, { grantStatus: done ? "completed" : "pending",
          grantCursor: items.at(-1)?.id ?? job.grantCursor ?? null, updatedAt: now });
        return { propagationComplete: done, cleanupPending: true, processed: items.length };
      }
      let channel;
      if (channelReference) {
        if (!channelSnapshot.exists || channelSnapshot.data()?.aclRevision !== job.aclRevision ||
            channelSnapshot.data()?.status === "deleting") {
          transaction.update(reference, { grantStatus: "superseded", updatedAt: now });
          return { propagationComplete: true, superseded: true, cleanupPending: true, processed: 0 };
        }
        channel = canonicalChannel(channelSnapshot, serverId, { allowArchived: true });
      }
      if (job.grantStatus === "completed") return {
        propagationComplete: true, cleanupPending: job.kind === "channelAccess", processed: 0,
      };
      let query = serverReference.collection("members").orderBy(FieldPath.documentId());
      if (job.grantCursor !== undefined && job.grantCursor !== null) query = query.startAfter(job.grantCursor);
      const page = await transaction.get(query.limit(pageSize + 1));
      const items = page.docs.slice(0, pageSize);
      const members = items.map((item) => {
        try { return canonicalMember(item, item.id, server); } catch { return null; }
      });
      for (let index = 0; index < items.length; index += 1) {
        const item = items[index];
        const member = members[index];
        if (channelReference) {
          if (member) writeChannelGrant({ db, transaction, serverId, channelId: job.channelId, channel, member, now });
          else {
            transaction.delete(channelReference.collection("accessGrants").doc(item.id));
            transaction.delete(db.doc(`users/${item.id}/serverChannelRefs/${serverChannelRefId(serverId, job.channelId)}`));
          }
        } else if (member) {
          transaction.set(db.doc(`users/${item.id}/clubs/${serverId}`), membershipMirror(serverId, server, member));
        }
      }
      const done = page.size <= pageSize;
      transaction.update(reference, {
        grantStatus: done ? "completed" : "pending",
        grantCursor: items.at(-1)?.id ?? job.grantCursor ?? null,
        ...(done && job.kind === "serverMetadata" ? { status: "completed", completedAt: now } : {}),
        updatedAt: now,
      });
      return { propagationComplete: done, cleanupPending: job.kind === "channelAccess", processed: items.length };
    });
  }
  return { processServerControlOutboxPage };
}

module.exports = { createServerConvergenceService };

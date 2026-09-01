const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions/v2");

const { writeAuditLog } = require("../utils/audit");

const REGION = "europe-west1";

// Global Chat moderation runs through firestore.rules, not through a
// callable: soft-deleting a public message is a single, narrowly-shaped
// document update that rules can authorize precisely (author OR
// `role` claim in moderator/admin/superAdmin, content frozen,
// authorship immutable), so per ADR-013 it stays a direct client write.
//
// What rules CANNOT do is leave a record. Every other moderator action in
// this project writes an adminAuditLogs entry from the Admin SDK
// (functions/admin/*), and a moderator reaching into a community channel
// and removing someone else's message is exactly the kind of action that
// should never be invisible. This trigger closes that gap: it fires after
// the soft delete lands and records who removed whose message.
//
// A member deleting their OWN message is not moderation and is not
// logged — that is ordinary use, and logging it would bury the real
// moderator actions in noise.
// The trigger's actual decision and payload, separated from the
// onDocumentUpdated() binding so it can be tested by calling it. The
// binding itself is configuration — region and document path — and is
// exercised by deploying, not by a unit test.
async function handleGlobalMessageModerated(event) {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();

  if (!before || !after) return;
  // Only the false -> true transition, so an unrelated later write
  // cannot re-log the same removal.
  if (before.isDeleted === true || after.isDeleted !== true) return;

  const actorId = after.deletedBy;
  const authorId = after.senderId;

  if (!actorId || actorId === authorId) return;

  try {
    await writeAuditLog({
      // Firestore triggers are at-least-once: the same event can be
      // delivered again after a transient failure, and an unconditional
      // add() would then record the same removal twice. The CloudEvent
      // id is stable across those retries, so deriving the document id
      // from it makes a redelivery overwrite its own entry instead of
      // creating a second one.
      entryId: `globalMessage_${event.id}`,
      caller: { uid: actorId },
      action: "delete_global_message",
      targetType: "globalMessage",
      targetId: event.params.messageId,
      targetLabel: after.senderName ?? null,
      details: {
        channelId: event.params.channelId,
        authorId,
        // The removed text, so a review can tell a justified removal
        // from an abusive one. The document itself keeps only "".
        removedContent: before.content ?? null,
      },
    });
  } catch (error) {
    // An audit write must never resurrect a message that has already
    // been removed for the community.
    logger.error("Failed to audit a Global Chat moderation action", {
      errorName: error?.name ?? null,
      errorCode: error?.code ?? null,
    });
  }
}

const onGlobalMessageModerated = onDocumentUpdated(
  {
    region: REGION,
    document: "globalChat/{channelId}/messages/{messageId}",
  },
  handleGlobalMessageModerated,
);

module.exports = { onGlobalMessageModerated, handleGlobalMessageModerated };

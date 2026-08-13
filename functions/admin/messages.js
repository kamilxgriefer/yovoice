// Privileged message removal.
//
// ONE callable covers every surface a message can live on, because the
// dangerous version of this feature is five near-identical callables that
// drift apart until one of them forgets a check.
//
// Two rules shape the whole file:
//
//  1. The client NEVER supplies a Firestore path. It supplies a bounded
//     `messageType` plus ids, and the path is derived here. A client that
//     could name its own path could name `users/{uid}` and have a super
//     admin's credentials delete it.
//  2. A direct message is only reachable through a report that names that
//     exact message in that exact conversation. There is deliberately no
//     way to list, search or browse private conversations — a super admin
//     can act on what was reported to them and nothing else.
//
// Removal is a REDACTION, not a hard delete: the document stays with its
// content stripped and a moderation tombstone in place, so replies and
// threading do not break and the act itself remains auditable. Stored
// media referenced by the message is deleted separately and best-effort.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const { requireActiveSuperAdmin } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const { writeAuditLog } = require("../utils/audit");

/// The complete set of surfaces this callable will act on. Anything not
/// named here is refused before a single read happens.
const MESSAGE_TYPES = Object.freeze({
  GLOBAL: "globalMessage",
  ROOM: "roomMessage",
  CLUB: "clubMessage",
  DIRECT: "directMessage",
});

const ALL_TYPES = new Set(Object.values(MESSAGE_TYPES));

/// Firestore ids may not be empty, contain a slash, or be a path segment
/// that escapes upward. Rejecting these is what keeps a derived path
/// derived — without it, `messageId = "../../users/victim"` walks out.
function safeId(value, field) {
  const id = normalizeText(value, 1500);
  if (!id) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  if (id.includes("/") || id === "." || id === "..") {
    throw new HttpsError("invalid-argument", `${field} is not a valid id.`);
  }
  return id;
}

/// Derives the document reference for a message from bounded inputs.
///
/// A Family Room is a Club with `type: family`, so it needs no branch of
/// its own here: its channels live at the same path, and the audit entry
/// records which it was.
function resolveMessageRef({ messageType, ids }) {
  switch (messageType) {
    case MESSAGE_TYPES.GLOBAL:
      return db
        .collection("globalChat")
        .doc(safeId(ids.channelId, "channelId"))
        .collection("messages")
        .doc(safeId(ids.messageId, "messageId"));

    case MESSAGE_TYPES.ROOM:
      return db
        .collection("rooms")
        .doc(safeId(ids.roomId, "roomId"))
        .collection("messages")
        .doc(safeId(ids.messageId, "messageId"));

    // Clubs and Family Rooms share this path by design.
    case MESSAGE_TYPES.CLUB:
      return db
        .collection("clubs")
        .doc(safeId(ids.clubId, "clubId"))
        .collection("channels")
        .doc(safeId(ids.channelId, "channelId"))
        .collection("messages")
        .doc(safeId(ids.messageId, "messageId"));

    case MESSAGE_TYPES.DIRECT:
      return db
        .collection("conversations")
        .doc(safeId(ids.conversationId, "conversationId"))
        .collection("messages")
        .doc(safeId(ids.messageId, "messageId"));

    default:
      throw new HttpsError("invalid-argument", "Unsupported message type.");
  }
}

/// The gate on private conversations.
///
/// A report must exist, be about THIS message, and be about THIS
/// conversation. A report naming the right message in a different
/// conversation is refused — otherwise one legitimate report would become
/// a key to any message id an admin cared to guess.
async function requireMatchingReport({ reportId, conversationId, messageId }) {
  if (!reportId) {
    throw new HttpsError(
      "permission-denied",
      "A direct message can only be removed through a report.",
    );
  }

  const snapshot = await db
    .collection("reports")
    .doc(safeId(reportId, "reportId"))
    .get();

  if (!snapshot.exists) {
    throw new HttpsError("not-found", "That report does not exist.");
  }

  const report = snapshot.data() ?? {};
  const targetMessage =
    report.targetMessageId ?? report.messageId ?? report.targetId ?? null;
  const targetConversation =
    report.targetConversationId ?? report.conversationId ?? null;

  if (targetMessage !== messageId || targetConversation !== conversationId) {
    throw new HttpsError(
      "permission-denied",
      "That report does not identify this message.",
    );
  }

  return report;
}

/// Best-effort removal of media the message referenced.
///
/// Never fatal: a message whose audio is already gone must still redact.
/// The outcome is reported in the audit entry rather than swallowed.
async function deleteAttachments(urls) {
  const results = [];
  for (const url of urls) {
    try {
      const bucket = getStorage().bucket();
      // Accepts both a gs:// path and a download URL's object segment.
      const match = String(url).match(/\/o\/([^?]+)/);
      const objectPath = match
        ? decodeURIComponent(match[1])
        : String(url).replace(/^gs:\/\/[^/]+\//, "");
      if (!objectPath || objectPath.startsWith("http")) {
        results.push({ url, deleted: false, reason: "unrecognised" });
        continue;
      }
      await bucket.file(objectPath).delete({ ignoreNotFound: true });
      results.push({ url, deleted: true });
    } catch (error) {
      results.push({ url, deleted: false, reason: error?.code ?? "error" });
    }
  }
  return results;
}

const adminDeleteMessage = onCall(
  { region: "europe-west1" },
  async (request) => {
    // Claim AND server-written role, and not banned. Mirrors what
    // firestore.rules requires of staff, so a revoked super admin cannot
    // act on a token that has not refreshed yet.
    const actor = await requireActiveSuperAdmin(request);

    const data = request.data ?? {};
    const messageType = String(data.messageType ?? "");
    if (!ALL_TYPES.has(messageType)) {
      throw new HttpsError("invalid-argument", "Unsupported message type.");
    }

    const reason = normalizeText(data.reason, 500);
    if (!reason) {
      throw new HttpsError("invalid-argument", "A reason is required.");
    }

    const ids = data.ids ?? {};
    const messageId = safeId(ids.messageId, "messageId");
    const reportId = data.reportId ? safeId(data.reportId, "reportId") : null;

    let conversationId = null;
    if (messageType === MESSAGE_TYPES.DIRECT) {
      conversationId = safeId(ids.conversationId, "conversationId");
      await requireMatchingReport({ reportId, conversationId, messageId });
    }

    const ref = resolveMessageRef({ messageType, ids });
    const snapshot = await ref.get();

    if (!snapshot.exists) {
      // Idempotent: a retry after a successful removal, or a message that
      // was never there, is reported rather than thrown at the caller as
      // a failure they cannot act on.
      await writeAuditLog({
        action: "adminDeleteMessage",
        caller: actor,
        targetType: messageType,
        targetId: messageId,
        details: { reason, reportId, outcome: "missing", ...ids },
      });
      return { outcome: "missing", redacted: false };
    }

    const message = snapshot.data() ?? {};

    if (message.isDeleted === true) {
      // Already redacted. Same idempotent answer, still audited.
      await writeAuditLog({
        action: "adminDeleteMessage",
        caller: actor,
        targetType: messageType,
        targetId: messageId,
        details: { reason, reportId, outcome: "alreadyRemoved", ...ids },
      });
      return { outcome: "alreadyRemoved", redacted: false };
    }

    const attachmentUrls = [
      message.audioUrl,
      message.imageUrl,
      message.mediaUrl,
      ...(Array.isArray(message.attachments) ? message.attachments : []),
    ].filter((value) => typeof value === "string" && value.length > 0);

    const media = await deleteAttachments(attachmentUrls);

    // The tombstone: identity of the author is kept so moderation history
    // stays meaningful, content and media are stripped, and the row
    // remains so replies pointing at it do not dangle.
    await ref.update({
      content: "",
      audioUrl: FieldValue.delete(),
      imageUrl: FieldValue.delete(),
      mediaUrl: FieldValue.delete(),
      attachments: FieldValue.delete(),
      isDeleted: true,
      deletedBy: actor.uid,
      deletedByRole: "superAdmin",
      deletedAt: FieldValue.serverTimestamp(),
      moderationRemoved: true,
    });

    // NOTE: the audit entry deliberately records WHAT was removed and by
    // whom — never the message body. Copying private content into
    // adminAuditLogs would move it somewhere with a different, broader
    // audience and defeat the point of removing it.
    await writeAuditLog({
      action: "adminDeleteMessage",
      caller: actor,
      targetType: messageType,
      targetId: messageId,
      details: {
        reason,
        authorId: message.senderId ?? message.authorId ?? null,
        reportId,
        outcome: "redacted",
        attachmentsRemoved: media.filter((item) => item.deleted).length,
        attachmentsFailed: media.filter((item) => !item.deleted).length,
        ...ids,
      },
    });

    return { outcome: "redacted", redacted: true };
  },
);

module.exports = {
  adminDeleteMessage,
  MESSAGE_TYPES,
  resolveMessageRef,
  safeId,
};

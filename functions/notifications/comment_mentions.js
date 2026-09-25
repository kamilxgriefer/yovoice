/**
 * @-mentions in Voice Moment and Yeel comments (ADR-213).
 *
 * The four comment callables accept an OPTIONAL `mentionUserIds` input: the
 * user ids the composer resolved from the viewer's own thread participants
 * and friends. The callable only proves the list is well formed (opaque
 * uids, the caller removed, duplicates removed, at most five) and records it
 * in a server-only document written in the SAME transaction as the comment.
 * Whether a listed person may actually be told — they can see the parent,
 * nobody has blocked anybody, both accounts are active — is decided by the
 * notification writer inside its own transaction and again at push time
 * (notifications/engagement_source.js), because audience and blocks can
 * change after the comment is written. An ineligible id is dropped silently
 * there, never refused here, so the response cannot be used to probe who
 * has blocked whom.
 *
 * The record lives beside the comment rather than in it: comment documents
 * are validated against exact key sets on every read path, and Voice Moment
 * comments are client-readable, so a field on the comment would either break
 * those readers or publish the list.
 */
const {
  fail,
  isValidOpaqueUid,
  timestampMillis,
} = require("../integrity/guards");

const MAX_COMMENT_MENTIONS = 5;
// A generous transport bound: a client resolving more candidates than this
// is malformed, not enthusiastic. The stored list is capped at five.
const MAX_COMMENT_MENTION_INPUT = 20;
const COMMENT_MENTION_KINDS = Object.freeze(["moment", "reel"]);

/**
 * Normalizes the optional callable input. Absent (or null) means "no
 * mentions", which keeps every installed client's request — and therefore
 * its idempotency input hash — byte for byte what it was.
 */
function normalizeMentionUserIds(value, actorId) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > MAX_COMMENT_MENTION_INPUT) {
    fail("invalid-argument", "mentionUserIds is invalid.");
  }
  const mentioned = [];
  for (const uid of value) {
    if (typeof uid !== "string" || !isValidOpaqueUid(uid)) {
      fail("invalid-argument", "mentionUserIds is invalid.");
    }
    if (uid === actorId || mentioned.includes(uid)) continue;
    if (mentioned.length < MAX_COMMENT_MENTIONS) mentioned.push(uid);
  }
  return mentioned;
}

function commentMentionDocumentId(kind, parentId, commentId) {
  if (!COMMENT_MENTION_KINDS.includes(kind)) {
    throw new TypeError("An engagement kind is required.");
  }
  return `${kind}_${parentId}_${commentId}`;
}

function commentMentionReference(db, kind, parentId, commentId) {
  return db.doc(
    `commentMentions/${commentMentionDocumentId(kind, parentId, commentId)}`,
  );
}

/** The exact document a comment transaction writes. */
function commentMentionRecord({
  kind,
  parentId,
  commentId,
  actorId,
  mentionUserIds,
  now,
}) {
  return {
    schemaVersion: 1,
    kind,
    parentId,
    commentId,
    actorId,
    mentionUserIds: [...mentionUserIds],
    createdAt: now,
  };
}

/** Writes the record inside the caller's transaction, when there is one. */
function writeCommentMentions(transaction, db, {
  kind,
  parentId,
  commentId,
  actorId,
  mentionUserIds,
  now,
}) {
  if (!Array.isArray(mentionUserIds) || mentionUserIds.length === 0) return;
  transaction.set(
    commentMentionReference(db, kind, parentId, commentId),
    commentMentionRecord({
      kind,
      parentId,
      commentId,
      actorId,
      mentionUserIds,
      now,
    }),
  );
}

function exactCommentMentions(snapshot, { kind, parentId, commentId }) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = [
    "actorId", "commentId", "createdAt", "kind", "mentionUserIds",
    "parentId", "schemaVersion",
  ];
  if (keys.length !== expected.length ||
      keys.some((key, index) => key !== expected[index]) ||
      data.schemaVersion !== 1 || data.kind !== kind ||
      data.parentId !== parentId || data.commentId !== commentId ||
      !isValidOpaqueUid(data.actorId) ||
      !Array.isArray(data.mentionUserIds) ||
      data.mentionUserIds.length < 1 ||
      data.mentionUserIds.length > MAX_COMMENT_MENTIONS ||
      data.mentionUserIds.some((uid) => !isValidOpaqueUid(uid)) ||
      new Set(data.mentionUserIds).size !== data.mentionUserIds.length ||
      data.mentionUserIds.includes(data.actorId) ||
      timestampMillis(data.createdAt) === null) {
    return null;
  }
  return data;
}

module.exports = {
  COMMENT_MENTION_KINDS,
  MAX_COMMENT_MENTIONS,
  MAX_COMMENT_MENTION_INPUT,
  commentMentionDocumentId,
  commentMentionRecord,
  commentMentionReference,
  exactCommentMentions,
  normalizeMentionUserIds,
  writeCommentMentions,
};

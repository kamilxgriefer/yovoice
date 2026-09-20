// Emoji reactions on Servers V1 text-channel messages, direct-message style.
//
// One reaction per person from the fixed direct-message vocabulary, stored as
// `reactions: { [uid]: emoji }` on clubs/{serverId}/channels/{channelId}/
// messages/{messageId}. The map is written ONLY here, through the Admin SDK:
// the messages rule in firestore.rules stays create/update/delete false for
// every V1 server, so no client predicate is widened.
//
// Who may react is derived inside this callable, never stored as a channel
// capability: `grantMatches` (authority.js) compares a restricted channel's
// stored grant to `capabilitiesFor` with an EXACT key count, so a new `react`
// key would invalidate every stored accessGrant and lock members out of their
// private channels. The derivation is: the channel's `read` capability
// (restricted grant included), a non-guest role, an active profile, a verified
// email and no live communication mute. That lets ordinary members react in
// announcements and rules channels, where only moderators may post.

const {
  consumeRateLimit,
  fail,
  isValidOpaqueUid,
  rateLimitReference,
  requireExactInput,
  requireId,
  requireRequestId,
} = require("../integrity/guards");
const { ALLOWED_DIRECT_REACTIONS } = require("../messaging/direct_integrity");
const { denied, readChannelAccess } = require("./authority");
const { createServerOperations } = require("./operations");

const SERVER_MESSAGE_REACTION_KIND = "server.channel.message.reaction.v1";
const SERVER_MESSAGE_REACTION_SCOPE = "server.channel.message.reaction";
// The direct-message reaction budget (direct_integrity.js DEFAULT_LIMITS).
const SERVER_MESSAGE_REACTION_LIMIT = Object.freeze({ maxEvents: 60, windowMs: 60_000 });
// A bound on the map so one popular message cannot grow without limit. A new
// reactor past it is refused; changing or removing an existing reaction is not.
const MAX_SERVER_MESSAGE_REACTORS = 500;
const CHAT_CHANNEL_KINDS = Object.freeze(["text", "announcements", "rules"]);
const REACTABLE_MESSAGE_TYPES = Object.freeze(["text", "gif", "image", "video"]);

function reactionInput(data) {
  const fields = ["serverId", "channelId", "messageId", "emoji", "requestId"];
  requireExactInput(data, fields, fields);
  const emoji = data.emoji;
  if (emoji !== null && (typeof emoji !== "string" || !ALLOWED_DIRECT_REACTIONS.includes(emoji))) {
    fail("invalid-argument", "emoji is not an allowed reaction.");
  }
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    messageId: requireId(data.messageId, "messageId"),
    emoji,
    requestId: requireRequestId(data.requestId),
  };
}

/**
 * The stored map, validated exactly: absent means none; anything that is not
 * a bounded map of opaque uid -> allowed emoji needs reconciliation and is
 * never silently repaired by a reaction write.
 */
function canonicalServerMessageReactions(value) {
  if (value === undefined) return {};
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("data-loss", "The server message reactions are malformed.");
  }
  const entries = Object.entries(value);
  if (entries.length > MAX_SERVER_MESSAGE_REACTORS ||
      entries.some(([uid, emoji]) => !isValidOpaqueUid(uid) ||
        typeof emoji !== "string" || !ALLOWED_DIRECT_REACTIONS.includes(emoji))) {
    fail("data-loss", "The server message reactions are malformed.");
  }
  return Object.fromEntries(entries);
}

function reactableMessage(snapshot, { serverId, channelId }) {
  if (!snapshot?.exists) fail("not-found", "This message no longer exists.");
  const message = snapshot.data() ?? {};
  if (message.clubId !== serverId || message.channelId !== channelId ||
      typeof message.senderId !== "string" || message.senderId.length < 1) {
    fail("data-loss", "The server message binding is invalid.");
  }
  if (message.isDeleted === true) {
    fail("failed-precondition", "This message cannot be reacted to.");
  }
  const type = message.type ?? "text";
  if (!REACTABLE_MESSAGE_TYPES.includes(type)) {
    fail("failed-precondition", "This message cannot be reacted to.");
  }
  return message;
}

function createServerMessageReactionService(dependencies) {
  const { db, Timestamp } = dependencies ?? {};
  if (!db?.runTransaction || !Timestamp?.fromMillis) {
    throw new TypeError("db and Timestamp are required.");
  }
  const operations = createServerOperations(dependencies);

  async function reactionAccess(transaction, uid, input) {
    const access = await readChannelAccess({
      db, transaction, uid, serverId: input.serverId, channelId: input.channelId, capability: "read",
    });
    // Guests are the demoted state an owner assigns; capabilitiesFor already
    // treats them as non-members for writing, and reacting is a write other
    // members see. A channel without a message thread has nothing to react to.
    if (access.member.role === "guest" || !CHAT_CHANNEL_KINDS.includes(access.channel.kind)) denied();
    return access;
  }

  async function setServerChannelMessageReactionV1(request) {
    const input = reactionInput(request.data);
    // operations.execute: verified email, a committed target-independent
    // attempt budget, then one transaction that re-checks the active profile
    // and communication mute and replays the ledger. A replay re-authorizes
    // below before it returns, so a receipt never outlives the access.
    return operations.execute(request, SERVER_MESSAGE_REACTION_KIND, input,
      async ({ transaction, auth, prior, now, nowMs }) => {
        const access = await reactionAccess(transaction, auth.uid, input);
        if (prior) return prior;
        const messageRef = access.channelReference.collection("messages").doc(input.messageId);
        const rateRef = rateLimitReference(db, SERVER_MESSAGE_REACTION_SCOPE, auth.uid);
        const [messageSnapshot, rateSnapshot] = await Promise.all([
          transaction.get(messageRef),
          transaction.get(rateRef),
        ]);
        const message = reactableMessage(messageSnapshot, input);
        const reactions = canonicalServerMessageReactions(message.reactions);
        const previous = Object.hasOwn(reactions, auth.uid) ? reactions[auth.uid] : null;
        if (input.emoji !== null && previous === null &&
            Object.keys(reactions).length >= MAX_SERVER_MESSAGE_REACTORS) {
          fail("resource-exhausted", "This message has reached its reaction limit.");
        }
        consumeRateLimit(transaction, rateSnapshot, {
          reference: rateRef,
          scope: SERVER_MESSAGE_REACTION_SCOPE,
          uid: auth.uid,
          now,
          nowMs,
          ...SERVER_MESSAGE_REACTION_LIMIT,
        });
        const changed = previous !== input.emoji;
        if (changed) {
          const next = { ...reactions };
          if (input.emoji === null) delete next[auth.uid];
          else next[auth.uid] = input.emoji;
          transaction.update(messageRef, { reactions: next });
        }
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          messageId: input.messageId,
          emoji: input.emoji,
          changed,
        };
      });
  }

  return Object.freeze({ setServerChannelMessageReactionV1 });
}

module.exports = {
  CHAT_CHANNEL_KINDS,
  MAX_SERVER_MESSAGE_REACTORS,
  REACTABLE_MESSAGE_TYPES,
  SERVER_MESSAGE_REACTION_KIND,
  SERVER_MESSAGE_REACTION_LIMIT,
  SERVER_MESSAGE_REACTION_SCOPE,
  canonicalServerMessageReactions,
  createServerMessageReactionService,
};

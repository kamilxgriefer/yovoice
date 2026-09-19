/**
 * "You were given a role" / "you were made owner" (ADR-212).
 *
 * PROMOTIONS ONLY. A demotion, a removal or a ban is deliberately silent:
 * an admin who can strip a role can otherwise also push a notification to
 * the person they stripped it from, as often as they can cycle the role,
 * which is a harassment vector with no product value. The member still sees
 * the change in the server itself.
 *
 * The write happens immediately AFTER the membership transaction commits,
 * not inside it. `setServerMemberRoleV1` and `transferServerOwnershipV1`
 * finish with writes, and the canonical notification writer needs eight
 * reads (account state, restrictions, blocks, ledger) — Firestore requires
 * every read before the first write, so folding those reads in would mean
 * reordering two of the most safety-critical transactions in the Servers
 * surface. A missed reassurance notice is a far smaller failure than that
 * risk, and the delivery ledger keeps a retry idempotent.
 *
 * The recipient's membership revision is the source generation: the row is
 * revalidated against it at write time and again at push time, so a
 * promotion that was undone before the push never rings.
 */
const { logger } = require("firebase-functions/v2");

const { ROLE_POWER } = require("../servers/contract");

function isPromotion(previousRole, nextRole) {
  const before = ROLE_POWER[previousRole];
  const after = ROLE_POWER[nextRole];
  return Number.isSafeInteger(before) && Number.isSafeInteger(after) &&
    after > before;
}

function serverRoleNotificationId(serverId, memberId, revision) {
  return `serverRole_${serverId}_${memberId}_${revision}`;
}

function serverRoleEventId(serverId, memberId, revision) {
  return `server-role:${serverId}:${memberId}:${revision}`;
}

/**
 * Creates the notifier the Servers runtime injects into the membership
 * service. `firestore` is explicit so tests and the runtime bind the same
 * database the rest of the service uses.
 */
function createServerRolePromotionNotifier({ firestore }) {
  if (!firestore?.doc) throw new TypeError("A Firestore instance is required.");
  return async function notifyServerRolePromotion({
    serverId,
    memberId,
    actorId,
    previousRole,
    nextRole,
    membershipRevision,
    serverName = null,
  }) {
    if (!isPromotion(previousRole, nextRole)) return "skipped:not-a-promotion";
    if (typeof serverId !== "string" || typeof memberId !== "string" ||
        typeof actorId !== "string" || memberId === actorId ||
        !Number.isSafeInteger(membershipRevision) || membershipRevision < 1) {
      return "skipped:invalid-parties";
    }
    // Required lazily: notifications/canonical.js binds the default
    // Firestore app at import, and the Servers services are constructed in
    // contexts (focused tests, isolated runtimes) that have none.
    const {
      createNotificationForEvent,
    } = require("./canonical");
    const {
      serverRoleSourceIsCurrent,
    } = require("./engagement_source");
    const notification = {
      type: "serverRole",
      actorId,
      targetId: serverId,
      sourcePath: `clubs/${serverId}/members/${memberId}`,
      sourceGeneration: String(membershipRevision),
    };
    try {
      return await createNotificationForEvent({
        eventId: serverRoleEventId(serverId, memberId, membershipRevision),
        recipientId: memberId,
        actorId,
        type: "serverRole",
        notificationId: serverRoleNotificationId(
          serverId,
          memberId,
          membershipRevision,
        ),
        targetId: serverId,
        targetLabel: typeof serverName === "string" ? serverName : null,
        sourcePath: notification.sourcePath,
        sourceGeneration: notification.sourceGeneration,
        firestore,
        validate: (transaction) => serverRoleSourceIsCurrent({
          recipientId: memberId,
          notification,
          reader: transaction,
          firestore,
        }),
      });
    } catch (error) {
      // The membership change already committed. A notification failure must
      // never turn a successful promotion into a client-visible error.
      logger.error("Server role notification failed", {
        code: error?.code ?? "unknown",
      });
      return "skipped:error";
    }
  };
}

module.exports = {
  createServerRolePromotionNotifier,
  isPromotion,
  serverRoleEventId,
  serverRoleNotificationId,
};

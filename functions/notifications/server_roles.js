/**
 * "You were given a role" / "you were made owner" (ADR-213).
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
 *
 * Silence on demotion is not on its own enough. `setServerMemberRoleV1`
 * increments `authorizationRevision` on EVERY role change, so an owner or
 * coOwner could demote (silent) and re-promote (push) in a loop: each
 * promotion minted a fresh notification id, a fresh bell row and a fresh
 * push, bounded only by the shared 120/min attempt budget — about sixty
 * lock-screen lines a minute at one member, carrying an actor name and a
 * server name the actor controls. The notice is therefore charged against a
 * per-actor-PER-RECIPIENT-PER-ROLE budget, the way comment mentions are
 * charged in engagement.js. Exhausting it drops the notice silently: the
 * role change itself always stands.
 */
const { logger } = require("firebase-functions/v2");
const { Timestamp } = require("firebase-admin/firestore");

const {
  consumeRateLimit,
  rateLimitReference,
} = require("../integrity/guards");
const { ROLE_POWER } = require("../servers/contract");

// One notice per (actor, recipient, role) per day. A real promotion chain
// (member -> moderator -> admin -> coOwner) is three distinct roles and
// announces each of them; demoting and re-promoting to a role the member
// already held today announces nothing.
const PROMOTION_BUDGET = Object.freeze({
  maxEvents: 1,
  windowMs: 24 * 60 * 60_000,
});

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
 * The budget key: actor, recipient and the role being announced. Keyed on
 * the actor so a noisy admin cannot exhaust another admin's budget, on the
 * recipient so promoting fifty different members is unaffected, and on the
 * role so the announcement follows the news rather than the revision
 * counter — a member cycled between `member` and `moderator` hears about
 * `moderator` once.
 */
function promotionBudgetKey(actorId, memberId, role) {
  return `${actorId}:${memberId}:${role}`;
}

/**
 * Charges one promotion notice. Returns false when the budget is spent,
 * which drops the notice — never the promotion.
 */
async function chargePromotionBudget(firestore, actorId, memberId, role, nowMs) {
  const uid = promotionBudgetKey(actorId, memberId, role);
  const reference = rateLimitReference(
    firestore,
    "notification.serverRole",
    uid,
  );
  try {
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      consumeRateLimit(transaction, snapshot, {
        reference,
        scope: "notification.serverRole",
        uid,
        now: Timestamp.fromMillis(nowMs),
        nowMs,
        ...PROMOTION_BUDGET,
      });
    });
    return true;
  } catch (error) {
    if (error?.code === "resource-exhausted" || error?.code === "data-loss") {
      return false;
    }
    throw error;
  }
}

/**
 * Creates the notifier the Servers runtime injects into the membership
 * service. `firestore` is explicit so tests and the runtime bind the same
 * database the rest of the service uses.
 */
function createServerRolePromotionNotifier({ firestore, clock = Date.now }) {
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
      const nowMs = clock();
      if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
        throw new TypeError("clock must return epoch milliseconds.");
      }
      // Charged before the eight-read writer runs, so a cycling actor pays
      // one small transaction instead of a full notification write.
      if (!(await chargePromotionBudget(
        firestore,
        actorId,
        memberId,
        nextRole,
        nowMs,
      ))) {
        logger.info("Server role notification throttled", { serverId });
        return "skipped:throttled";
      }
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
  PROMOTION_BUDGET,
  chargePromotionBudget,
  createServerRolePromotionNotifier,
  isPromotion,
  promotionBudgetKey,
  serverRoleEventId,
  serverRoleNotificationId,
};

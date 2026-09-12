const {
  activeProfile, assertLedgerReplay, assertNotRestricted, consumeRateLimit,
  ledgerData, operationIdentity, rateLimitReference, requireActor,
  transactionGetAll,
} = require("../integrity/guards");

const DEFAULT_SERVER_LIMITS = Object.freeze({
  attempts: Object.freeze({ maxEvents: 120, windowMs: 60_000 }),
  creation: Object.freeze({ maxEvents: 30, windowMs: 60 * 60_000 }),
});

function createServerOperations({ db, Timestamp, clock = Date.now, limits = DEFAULT_SERVER_LIMITS }) {
  if (!db?.runTransaction || !Timestamp?.fromMillis) throw new TypeError("db and Timestamp are required.");
  async function execute(request, kind, input, work, { creation = false, verified = true, allowRestricted = false } = {}) {
    const auth = requireActor(request, { verified });
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) throw new TypeError("clock must return epoch milliseconds.");
    const now = Timestamp.fromMillis(nowMs);
    const { requestId, ...operationInput } = input;
    const identity = operationIdentity(kind, auth.uid, requestId, operationInput);
    const ledgerReference = db.doc(`integrityOperationLedgers/${identity.id}`);
    const actorReference = db.doc(`users/${auth.uid}`);
    const restrictionReference = db.doc(`restrictions/${auth.uid}`);
    const scopes = [{ scope: "server.v1.attempt", config: limits.attempts }];
    if (creation) scopes.push({ scope: "server.v1.create", config: limits.creation });
    const rates = scopes.map((item) => ({ ...item, reference: rateLimitReference(db, item.scope, auth.uid) }));

    // This target-independent budget commits before authorization reads.
    // Refused and replayed attempts cannot amplify unbounded target work.
    await db.runTransaction(async (transaction) => {
      const [profile, restriction, ...snapshots] = await transactionGetAll(
        transaction, actorReference, restrictionReference, ...rates.map((rate) => rate.reference),
      );
      activeProfile(profile, "Your");
      if (!allowRestricted) assertNotRestricted(restriction, "Your", nowMs);
      rates.forEach((rate, index) => consumeRateLimit(transaction, snapshots[index], {
        reference: rate.reference, scope: rate.scope, uid: auth.uid,
        now, nowMs, ...rate.config,
      }));
    });

    return db.runTransaction(async (transaction) => {
      const [ledger, profileSnapshot, restriction] = await transactionGetAll(
        transaction, ledgerReference, actorReference, restrictionReference,
      );
      const profile = activeProfile(profileSnapshot, "Your");
      if (!allowRestricted) assertNotRestricted(restriction, "Your", nowMs);
      const prior = assertLedgerReplay(ledger, { kind, uid: auth.uid, inputHash: identity.inputHash });
      // Each operation reauthorizes before returning prior. Receipts carry no
      // permission and never restore access revoked since the first request.
      const result = await work({ transaction, auth, profile, prior, now, nowMs, identity });
      if (!prior) transaction.create(ledgerReference, ledgerData({
        kind, uid: auth.uid, requestId, inputHash: identity.inputHash, result, now,
      }));
      return result;
    });
  }
  return { execute };
}

module.exports = { DEFAULT_SERVER_LIMITS, createServerOperations };

// The Page lapse TRANSITIONS (ADR-233 §2.8, owner decision O3): when the
// owner's YO Voice VIP ends, the Page turns read-only for 30 days and is then
// hidden; nothing is ever deleted, and a returning capability restores it.
//
// Every transition runs in ONE transaction (reconcilePage) that re-reads
// users/{P}, entitlements/{P}, vipGrants/{P}, pages/{P}, pageVisibility/v1
// and appConfig/pagesV1, derives the capability THERE and writes pages/{P}
// and the visibility index together. A stale reader (a sweep that looked at
// the grant a minute ago, a trigger delivered out of order) therefore can
// never overwrite a restore: whoever commits last derived from what is true
// at its own commit.
//
// Writers of transitions:
//   1. pagesMaintenance, hourly slice (sweep): (a) active Pages without
//      capability -> readOnly; (b) readOnly past 30 days -> hidden, and the
//      Day-23 notice; (c) readOnly or hidden Pages whose capability is back
//      -> active. At most 5 x 200 Pages a run, cursor-resumable.
//   2. onPageCapabilityEntitlementChanged / onPageCapabilityGrantChanged, on
//      entitlements/{uid} and vipGrants/{uid}: re-derive immediately.
//   3. every Pages write path restores live (lifecycle, posts); 4. reads
//      apply the 30-day boundary (lapse.js).
//
// appConfig/pagesV1.lapseEnabled false (the emergency brake; also the state
// of a missing or malformed switch) freezes every DOWNGRADE here; restores
// still run.
//
// The owner is told twice (R12): a `pageLapse` row at Day 0 (read-only) and
// at Day 23 (hidden in 7 days). Neither is written while the owner's own
// deletion of the Page is on record (pageDeletions/{P}, ADR-236): both say
// "nothing is deleted", which is not true of a Page on a deletion timer, and
// that owner already has the date and "Przywróć stronę" in front of them.
// The badge follows by itself: a status change
// fires onPageBadgeSourceChanged, whose derivation also re-checks the
// canonical grant for the rosette bit.

const { FieldPath, Timestamp } = require("firebase-admin/firestore");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const defaultLogger = require("firebase-functions/logger");

const { timestampMillis, transactionGetAll } = require("../integrity/guards");
const { derivePagesCapabilityFromData, pagesCapabilityReferences } = require("./access");
const {
  PAGES_ACTIVATION_PATH,
  canonicalPagesActivation,
  readPagesActivation,
} = require("./activation");
const { derivePageListed, pageMalformedReason } = require("./contract");
const { PAGE_READ_ONLY_WINDOW_MS } = require("./lapse");
const { PAGE_LAPSE_WARNING_AFTER_MS, pageLapseNotice } = require("./report_contract");
const {
  applyPageVisibilityInTransaction,
  pageVisibilityReference,
} = require("./visibility");

const REGION = "europe-west1";
const LAPSE_STATE_ID = "lapseSweep";
const LAPSE_SWEEP_EVERY_MS = 60 * 60 * 1000;
const LAPSE_PHASES = Object.freeze(["active", "readOnly", "hidden"]);
const PAGES_LAPSE_LIMITS = Object.freeze({ batchSize: 200, batchesPerRun: 5 });

// The exact sweep query (pages: status ASC, lapsedAt ASC, __name__ ASC). The
// index smoke and the emulator index test run this same builder (ADR-007).
const PAGES_LAPSE_QUERIES = Object.freeze({
  byStatus: (db, status) => db.collection("pages")
    .where("status", "==", status)
    .orderBy("lapsedAt", "asc")
    .orderBy(FieldPath.documentId(), "asc"),
});

function dataOf(snapshot) {
  return snapshot?.exists ? (snapshot.data() ?? null) : null;
}

function lapseNoticeReference(db, pageId, phase, lapsedAtMs) {
  return db.doc(`users/${pageId}/notifications/${pageLapseNotice({
    phase, pageId, lapsedAtMs, now: null,
  }).id}`);
}

/**
 * What a Page needs, from already-read documents (pure). One of:
 *   restore | readOnly | hidden | warn | none | frozen
 */
function lapseDecision({ page, capabilityAllowed, lapseEnabled, nowMs, warned = false }) {
  if (!page) return "none";
  if (capabilityAllowed) return page.status === "active" ? "none" : "restore";
  if (lapseEnabled !== true) return page.status === "active" ? "frozen" : "none";
  if (page.status === "active") return "readOnly";
  if (page.status !== "readOnly") return "none";
  const lapsedAtMs = timestampMillis(page.lapsedAt);
  if (lapsedAtMs === null) return "none";
  const elapsed = nowMs - lapsedAtMs;
  if (elapsed >= PAGE_READ_ONLY_WINDOW_MS) return "hidden";
  if (elapsed >= PAGE_LAPSE_WARNING_AFTER_MS && !warned) return "warn";
  return "none";
}

function createPagesLapseService({
  firestore,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  limits = PAGES_LAPSE_LIMITS,
}) {
  if (!firestore?.doc || typeof TimestampImpl?.fromMillis !== "function" ||
      typeof clock !== "function") {
    throw new TypeError("firestore, Timestamp and clock are required.");
  }

  function timing() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  /**
   * Re-derives one Page inside one transaction and writes the transition it
   * needs, if any. {outcome: restored | readOnly | hidden | warned | none |
   * frozen | noPage | malformed}.
   */
  async function reconcilePage(pageId) {
    const { nowMs, now } = timing();
    const pageRef = firestore.doc(`pages/${pageId}`);
    return firestore.runTransaction(async (transaction) => {
      const [userSnapshot, entitlementSnapshot, grantSnapshot, pageSnapshot,
        visibilitySnapshot, activationSnapshot, deletionSnapshot] = await transactionGetAll(
        transaction,
        ...pagesCapabilityReferences(firestore, pageId),
        pageRef,
        pageVisibilityReference(firestore),
        firestore.doc(PAGES_ACTIVATION_PATH),
        // ADR-236: the owner's own deletion of this Page, pending or running.
        firestore.doc(`pageDeletions/${pageId}`),
      );
      if (!pageSnapshot.exists) return { outcome: "noPage" };
      const reason = pageMalformedReason(pageSnapshot.data(), pageId);
      if (reason !== null) {
        // A transition is never written onto a half-understood Page; every
        // reader already treats it as unviewable.
        logger.error("pages lapse skipped a malformed page", { reason });
        return { outcome: "malformed" };
      }
      const page = pageSnapshot.data();
      const activation = canonicalPagesActivation(activationSnapshot);
      const capability = derivePagesCapabilityFromData({
        user: dataOf(userSnapshot),
        entitlement: dataOf(entitlementSnapshot),
        grant: dataOf(grantSnapshot),
        now: nowMs,
      });
      const lapsedAtMs = timestampMillis(page.lapsedAt);
      let warningSnapshot = null;
      if (!capability.allowed && page.status === "readOnly" && lapsedAtMs !== null) {
        [warningSnapshot] = await transactionGetAll(
          transaction,
          lapseNoticeReference(firestore, pageId, "hidingSoon", lapsedAtMs),
        );
      }
      const decision = lapseDecision({
        page,
        capabilityAllowed: capability.allowed,
        lapseEnabled: activation.lapseEnabled,
        nowMs,
        warned: warningSnapshot?.exists === true,
      });
      // The owner's notices land only on a live account document, and never
      // beside the owner's own deletion of the Page: "nothing is deleted"
      // would be untrue (the transition itself is still written).
      const notifyOwner = userSnapshot.exists && !deletionSnapshot.exists;
      if (decision === "none" || decision === "frozen") return { outcome: decision };
      if (decision === "warn") {
        if (notifyOwner) {
          const notice = pageLapseNotice({ phase: "hidingSoon", pageId, lapsedAtMs, now });
          transaction.set(firestore.doc(`users/${pageId}/notifications/${notice.id}`), notice.data);
        }
        return { outcome: "warned" };
      }
      const changes = decision === "restore"
        ? { status: "active", lapsedAt: null }
        : decision === "readOnly"
          ? { status: "readOnly", lapsedAt: now }
          : { status: "hidden" };
      const next = { ...page, ...changes, updatedAt: now };
      next.listed = derivePageListed(next);
      transaction.update(pageRef, { ...changes, listed: next.listed, updatedAt: now });
      applyPageVisibilityInTransaction(transaction, {
        db: firestore,
        snapshot: visibilitySnapshot,
        pageId,
        page: next,
        now,
        logger,
        // Hiding a Page must never be refused by a broken index; every
        // reader re-checks the Page document per item.
        safetyAction: decision !== "restore",
      });
      if (decision === "readOnly" && notifyOwner) {
        const notice = pageLapseNotice({ phase: "readOnly", pageId, lapsedAtMs: nowMs, now });
        transaction.set(firestore.doc(`users/${pageId}/notifications/${notice.id}`), notice.data);
      }
      const outcome = decision === "restore" ? "restored" : decision;
      logger.info("pages lapse transition", { outcome });
      return { outcome };
    });
  }

  /// A capability source (entitlements/{uid} or vipGrants/{uid}) changed.
  /// One plain read when the account runs no Page.
  async function handleCapabilityChange(uid) {
    const snapshot = await firestore.doc(`pages/${uid}`).get();
    if (!snapshot.exists) return { outcome: "noPage" };
    return reconcilePage(uid);
  }

  // ----------------------------------------------------------- sweep

  function readCursor(state) {
    const phase = LAPSE_PHASES.includes(state.phase) ? state.phase : null;
    const afterId = typeof state.afterId === "string" && state.afterId.length > 0
      ? state.afterId
      : null;
    const afterLapsedAtMs = Number.isSafeInteger(state.afterLapsedAtMs)
      ? state.afterLapsedAtMs
      : null;
    return { phase, afterId, afterLapsedAtMs };
  }

  /**
   * The hourly slice. Runs when a pass is in progress or the last one
   * finished an hour ago. Bounded: at most batchesPerRun x batchSize Pages,
   * each checked from one getAll of its three capability documents; only a
   * Page that needs a transition pays for a transaction.
   */
  async function sweep({ force = false } = {}) {
    const { nowMs, now } = timing();
    const stateRef = firestore.doc(`pageMaintenanceState/${LAPSE_STATE_ID}`);
    const stateSnapshot = await stateRef.get();
    const state = stateSnapshot.exists ? (stateSnapshot.data() ?? {}) : {};
    let { phase, afterId, afterLapsedAtMs } = readCursor(state);
    const lastCompletedMs = timestampMillis(state.lastCompletedAt);
    if (!force && phase === null && lastCompletedMs !== null &&
        nowMs - lastCompletedMs < LAPSE_SWEEP_EVERY_MS) {
      return { ran: false };
    }
    const activation = await readPagesActivation({ db: firestore, logger });
    if (phase === null) {
      phase = LAPSE_PHASES[0];
      afterId = null;
      afterLapsedAtMs = null;
    }
    const line = { ran: true, scanned: 0, transitions: 0, malformed: 0, completed: false };
    let completedAt = state.lastCompletedAt ?? null;
    for (let batch = 0; batch < limits.batchesPerRun; batch += 1) {
      // Downgrading an active Page is the one thing the brake freezes; the
      // pass skips that whole phase instead of scanning for nothing.
      if (phase === "active" && activation.lapseEnabled !== true) {
        phase = "readOnly";
        afterId = null;
        afterLapsedAtMs = null;
      }
      let query = PAGES_LAPSE_QUERIES.byStatus(firestore, phase).limit(limits.batchSize);
      if (afterId !== null) {
        query = query.startAfter(
          afterLapsedAtMs === null ? null : TimestampImpl.fromMillis(afterLapsedAtMs),
          afterId,
        );
      }
      const snapshot = await query.get();
      line.scanned += snapshot.size;
      const pages = snapshot.docs.map((document) => ({
        id: document.id,
        data: document.data() ?? {},
      }));
      const references = [];
      for (const entry of pages) {
        references.push(...pagesCapabilityReferences(firestore, entry.id));
        const lapsedAtMs = timestampMillis(entry.data.lapsedAt);
        references.push(entry.data.status === "readOnly" && lapsedAtMs !== null
          ? lapseNoticeReference(firestore, entry.id, "hidingSoon", lapsedAtMs)
          : firestore.doc(`pages/${entry.id}`));
      }
      const snapshots = references.length > 0 ? await firestore.getAll(...references) : [];
      for (let index = 0; index < pages.length; index += 1) {
        const entry = pages[index];
        if (pageMalformedReason(entry.data, entry.id) !== null) {
          line.malformed += 1;
          continue;
        }
        const [user, entitlement, grant, warning] = snapshots.slice(index * 4, index * 4 + 4);
        const capability = derivePagesCapabilityFromData({
          user: dataOf(user),
          entitlement: dataOf(entitlement),
          grant: dataOf(grant),
          now: nowMs,
        });
        const decision = lapseDecision({
          page: entry.data,
          capabilityAllowed: capability.allowed,
          lapseEnabled: activation.lapseEnabled,
          nowMs,
          warned: entry.data.status === "readOnly" && warning?.exists === true,
        });
        if (decision === "none" || decision === "frozen") continue;
        // The transaction re-derives everything; this read only chose it.
        const outcome = await reconcilePage(entry.id);
        if (!["none", "frozen", "noPage", "malformed"].includes(outcome.outcome)) {
          line.transitions += 1;
        }
      }
      const last = pages[pages.length - 1] ?? null;
      if (pages.length < limits.batchSize) {
        const nextPhase = LAPSE_PHASES[LAPSE_PHASES.indexOf(phase) + 1] ?? null;
        afterId = null;
        afterLapsedAtMs = null;
        if (nextPhase === null) {
          phase = null;
          completedAt = now;
          line.completed = true;
          break;
        }
        phase = nextPhase;
      } else {
        afterId = last.id;
        afterLapsedAtMs = timestampMillis(last.data.lapsedAt);
      }
    }
    if (line.malformed > 0) logger.error("pages lapse sweep found malformed pages", { count: line.malformed });
    await stateRef.set({
      schemaVersion: 1,
      phase,
      afterId,
      afterLapsedAtMs,
      lastCompletedAt: completedAt,
      updatedAt: now,
    });
    return line;
  }

  return Object.freeze({ handleCapabilityChange, reconcilePage, sweep });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    defaultService = createPagesLapseService({ firestore: db });
  }
  return defaultService;
}

// Capability sources: a grant revoked or re-granted, a paid entitlement
// changing. Only the uid is taken from the event; state is re-read inside
// the transaction, so out-of-order deliveries converge.
const onPageCapabilityEntitlementChanged = onDocumentWritten(
  { document: "entitlements/{uid}", region: REGION },
  async (event) => {
    await service().handleCapabilityChange(event.params.uid);
  },
);

const onPageCapabilityGrantChanged = onDocumentWritten(
  { document: "vipGrants/{uid}", region: REGION },
  async (event) => {
    await service().handleCapabilityChange(event.params.uid);
  },
);

module.exports = {
  LAPSE_PHASES,
  LAPSE_STATE_ID,
  LAPSE_SWEEP_EVERY_MS,
  PAGES_LAPSE_LIMITS,
  PAGES_LAPSE_QUERIES,
  createPagesLapseService,
  lapseDecision,
  onPageCapabilityEntitlementChanged,
  onPageCapabilityGrantChanged,
};
